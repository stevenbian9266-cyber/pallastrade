# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: 权限注册表（2026-08-16 权限体系重构）
  #
  # 单一事实源：admin 后台「功能权限 / 数据权限」矩阵可配置的资源、可用操作
  # 与可数据过滤字段。UI 渲染权限矩阵、Ability 判定、nav:validate 校验都读它。
  #
  # PALLAS-CUSTOM (2026-09-11, PRD-20260911-promotions-promo-batch5b): 一个 capability
  # 可以覆盖**多个模型**——后台「促销管理」同时管 Promotion、PromotionRule（规则弹窗）、
  # PromotionAction（动作弹窗），而各控制器用各自的模型类做 `authorize!`，所以注册表
  # 必须声明覆盖集合；否则 DB 驱动角色拿到 `promotions.update` 仍然改不了规则/动作。
  #   * `models`      —— 该资源覆盖的模型集合（默认 `[model_class]`）
  #   * `model_class` —— 向后兼容：主模型（= `models.first`）
  #
  # @example
  #   PallasTrade::PermissionRegistry.register(:orders,
  #     model_class: PallasTrade::Order, actions: %w[read create update destroy export], data_fields: %w[user_id store_id channel_id])
  class PermissionRegistry
    Entry = Struct.new(:resource, :model_class, :label, :actions, :data_fields, :models, keyword_init: true)

    # `validate!` 的分级与错误码（error = 结构性错误；warning = 提示）
    VALIDATION_CODES = {
      invalid_action: :error,
      invalid_model_class: :error,
      invalid_data_field: :error,
      missing_data_scope_path: :error,
      model_class_mismatch: :error,
      duplicate_model: :warning,
      resource_without_model: :warning
    }.freeze

    @entries = {}

    class << self
      # rubocop:disable Metrics/ParameterLists -- 注册接口保持扁平关键字（resource/model_class/label/actions/data_fields/models），
      # 改哈希会破坏既有调用方与可读性；已有 13 处调用沿此签名。
      def register(resource, model_class: nil, label: nil, actions: nil, data_fields: [], models: nil)
        resource = resource.to_sym
        covered = Array(models.presence || model_class).compact
        @entries[resource] = Entry.new(
          resource: resource,
          model_class: model_class || covered.first,
          label: label || resource.to_s.humanize,
          actions: (actions || %w[read create update destroy]).map(&:to_s),
          data_fields: data_fields.map(&:to_s),
          models: covered
        )
      end

      # @param resource [Symbol, String]
      # @return [Entry, nil]
      def [](resource)
        @entries[resource.to_sym]
      end

      def each(&)
        @entries.each(&)
      end

      def resources
        @entries.keys
      end

      # 快照 / 还原注册表（spec 与热重载用）。
      #
      # @return [Hash{Symbol => Entry}]
      def snapshot
        @entries.dup
      end

      # @param entries [Hash{Symbol => Entry}]
      # @return [Hash{Symbol => Entry}]
      def replace_entries!(entries)
        @entries = entries.dup
      end

      # 覆盖了该模型的全部资源（一个模型可能被多个资源覆盖，CanCan 语义为并集）
      #
      # @return [Array<Symbol>]
      def resources_for_model(model)
        model_name = model.respond_to?(:name) ? model.name : model.to_s
        @entries.values.select { |entry| entry.models.any? { |m| m.name == model_name } }.map(&:resource)
      end

      # 注册表自洽校验（models / actions / data_fields / model_class 一致性）
      #
      # @return [Array<Hash>] `[{ level:, code:, resource:, message: }]`，error 在前
      def validate!
        issues = @entries.values.flat_map { |entry| entry_issues(entry) } + duplicate_model_issues
        issues.sort_by { |issue| issue[:level] == :error ? 0 : 1 }
      end

      def valid?
        validate!.none? { |issue| issue[:level] == :error }
      end

      def reset!
        @entries.clear
      end

      private

      def issue(code, resource, message)
        { level: VALIDATION_CODES.fetch(code), code: code, resource: resource, message: message }
      end

      def entry_issues(entry)
        model_class_issues(entry) + action_issues(entry) + data_field_issues(entry)
      end

      def model_class_issues(entry)
        issues = []

        if entry.models.empty?
          issues << issue(:resource_without_model, entry.resource,
                          "资源 #{entry.resource.inspect} 未声明模型（UI-only 资源可接受，Ability 将以资源符号授权）")
        end

        entry.models.each do |model|
          next if model.is_a?(Class) && model < ActiveRecord::Base

          issues << issue(:invalid_model_class, entry.resource,
                          "资源 #{entry.resource.inspect} 的模型 #{model.inspect} 不是 ActiveRecord::Base 子类")
        end

        if entry.model_class && entry.models.first && entry.model_class != entry.models.first
          issues << issue(:model_class_mismatch, entry.resource,
                          "资源 #{entry.resource.inspect} 的 model_class=#{entry.model_class} 与 models.first=#{entry.models.first} 不一致")
        end

        issues
      end

      def action_issues(entry)
        allowed = PallasTrade::RolePermission::FUNCTION_ACTIONS

        entry.actions.reject { |action| allowed.include?(action) }.map do |action|
          issue(:invalid_action, entry.resource,
                "资源 #{entry.resource.inspect} 的动作 #{action.inspect} 不在 RolePermission::FUNCTION_ACTIONS #{allowed.inspect} 内")
        end
      end

      def data_field_issues(entry)
        entry.data_fields.flat_map { |field| data_field_issues_for(entry, field) }
      end

      def data_field_issues_for(entry, field)
        carriers = entry.models.select { |model| column_owner?(model, field) }

        if carriers.empty?
          reachable = entry.models.any? { |model| data_scope_owner(model, field, 2) }
          next_issues = []

          unless reachable
            next_issues << issue(:invalid_data_field, entry.resource,
                                 "资源 #{entry.resource.inspect} 的数据字段 #{field.inspect} 不是任一覆盖模型 " \
                                 "（#{entry.models.map(&:name).join(', ')}）的真实列，也无法经关联到达")
          end

          return next_issues
        end

        (entry.models - carriers).filter_map do |model|
          next if data_scope_path?(model, carriers, field)

          issue(:missing_data_scope_path, entry.resource,
                "资源 #{entry.resource.inspect} 的 #{model.name} 没有 #{field.inspect} 列，且无法经关联到达持有该列的模型 " \
                "(#{carriers.map(&:name).join(', ')})")
        end
      end

      def column_owner?(model, field)
        model.respond_to?(:column_names) && model.column_names.include?(field)
      end

      # 该模型能否经 belongs_to 关联到达持有数据列的模型（如
      # PromotionRule → promotion.store_id）；Ability 用同一规则生成数据范围条件。
      def data_scope_path?(model, carriers, field)
        return true unless model.respond_to?(:reflect_on_all_associations)

        model.reflect_on_all_associations(:belongs_to).any? do |association|
          column_owner?(association.klass, field) && carriers.include?(association.klass)
        rescue StandardError
          false
        end
      end

      # 沿 belongs_to 链（深度 ≤ depth）查找持有该列的模型。
      def data_scope_owner(model, field, depth)
        return nil if depth.negative? || !model.respond_to?(:reflect_on_all_associations)
        return model if column_owner?(model, field)

        model.reflect_on_all_associations(:belongs_to).lazy.filter_map do |association|
          data_scope_owner(association.klass, field, depth - 1)
        rescue StandardError
          nil
        end.first
      end

      def duplicate_model_issues
        entry_by_model = Hash.new { |hash, key| hash[key] = [] }

        @entries.each_value do |entry|
          entry.models.each { |model| entry_by_model[model.name] << entry.resource }
        end

        entry_by_model.filter_map do |model_name, resource_names|
          next if resource_names.uniq.size < 2

          issue(:duplicate_model, resource_names.first,
                "模型 #{model_name} 被多个资源覆盖（#{resource_names.uniq.join(', ')}）——Ability 以并集生效，请确认划分意图")
        end
      end
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
