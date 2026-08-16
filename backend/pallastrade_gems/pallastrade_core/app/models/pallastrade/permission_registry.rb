# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: 权限注册表（2026-08-16 权限体系重构）
  #
  # 单一事实源：admin 后台「功能权限 / 数据权限」矩阵可配置的资源、可用操作
  # 与可数据过滤字段。UI 渲染权限矩阵、Ability 判定、nav:validate 校验都读它。
  #
  # @example
  #   PallasTrade::PermissionRegistry.register(:orders,
  #     model_class: PallasTrade::Order, actions: %w[read create update destroy export], data_fields: %w[user_id store_id channel_id])
  class PermissionRegistry
    Entry = Struct.new(:resource, :model_class, :label, :actions, :data_fields, keyword_init: true)

    @entries = {}

    class << self
      def register(resource, model_class: nil, label: nil, actions: nil, data_fields: [])
        resource = resource.to_sym
        @entries[resource] = Entry.new(
          resource: resource,
          model_class: model_class,
          label: label || resource.to_s.humanize,
          actions: (actions || %w[read create update destroy]).map(&:to_s),
          data_fields: data_fields.map(&:to_s)
        )
      end

      # @param resource [Symbol, String]
      # @return [Entry, nil]
      def [](resource)
        @entries[resource.to_sym]
      end

      def each(&block)
        @entries.each(&block)
      end

      def resources
        @entries.keys
      end

      def reset!
        @entries.clear
      end
    end
  end
end
