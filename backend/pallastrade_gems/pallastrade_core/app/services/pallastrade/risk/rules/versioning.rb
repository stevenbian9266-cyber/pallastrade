# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# `Risk::Rules::Versioning` —— 规则版本流转的**唯一入口**：草稿 / 发布 / 金丝雀 / **回滚** / 停用。
#
# 语义（唯一权威）：
#   * 每次变更 = 一个新版本（版本号单调递增，草稿校验不过**不落库**）；
#   * 发布 = 该版本 `published` 并成为 `active_version_id`，**旧生效版转 `archived`**（内容不动）；
#   * 金丝雀 = 指定一个已发布版本 + 百分比（0 = 关闭金丝雀）；
#   * **回滚** = 以历史版本内容**生成新版本**（`rolled_back: true` + `source_version` + `reason`）并生效，
#     历史版本原样保留 —— 「回滚」不是改写历史，而是新的一步；
#   * 每个动作都写审计；发布/回滚额外发事件（事件系统未启用或发布失败**不阻断**动作，
#     因为版本状态已经落库，事件只是通知）。
#
# 铁律：零 provider、零资金副作用、不动订单/支付。
module PallasTrade
  module Risk
    module Rules
      class Versioning
        prepend PallasTrade::ServiceModule::Base

        EVENT_VERSION_PUBLISHED = 'risk.rule_version_published'
        EVENT_VERSION_ROLLED_BACK = 'risk.rule_version_rolled_back'

        AUDIT_VERSION_CREATED = 'risk_rule_version_created'
        AUDIT_VERSION_PUBLISHED = 'risk_rule_version_published'
        AUDIT_CANARY_UPDATED = 'risk_rule_canary_updated'
        AUDIT_VERSION_ROLLED_BACK = 'risk_rule_version_rolled_back'
        AUDIT_SET_ACTIVATED = 'risk_rule_set_activated'
        AUDIT_SET_DEACTIVATED = 'risk_rule_set_deactivated'

        MIN_PERCENT = 0
        MAX_PERCENT = PallasTrade::RiskRuleSet::MAX_CANARY_PERCENT

        # 类级便捷入口（与仓库既有 `X.call` 风格一致；内部同一份实现，口径不分叉）
        class << self
          def create_draft(**kwargs) = new.create_draft(**kwargs)
          def publish(**kwargs) = new.publish(**kwargs)
          def set_canary(**kwargs) = new.set_canary(**kwargs)
          def rollback(**kwargs) = new.rollback(**kwargs)
          def activate(**kwargs) = new.activate(**kwargs)
          def deactivate(**kwargs) = new.deactivate(**kwargs)
        end

        # 新建草稿版本（校验不过 → 不落库）
        # @return [PallasTrade::ServiceModule::Result] success(RiskRuleVersion) / failure(错误列表, 错误文本)
        def create_draft(rule_set:, rules:, reason: nil, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          schema = Schema.call(rules: rules)
          return failure(schema.value, schema.error.to_s) if schema.failure?

          record = nil
          ActiveRecord::Base.transaction do
            record = rule_set.versions.create!(
              version: next_version(rule_set),
              state: 'draft',
              rules: schema.value,
              reason: reason.to_s.strip.presence,
              created_by: creator_for(actor)
            )
          end

          record_audit(AUDIT_VERSION_CREATED, rule_set, actor,
                       version: record.version, rules_count: record.rules_count)
          success(record)
        end

        # 发布：该版本生效，旧生效版归档（内容不可变）
        def publish(rule_set:, version:, reason: nil, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          record = resolve_version(rule_set, version)
          return failure(nil, 'Version not found for this rule set') if record.nil?
          return failure(nil, 'Only draft or published versions can be published') if record.archived?

          previous_version = rule_set.active_version
          ActiveRecord::Base.transaction do
            archive_other(rule_set, record)
            record.update!(state: 'published', published_at: record.published_at || Time.current,
                           reason: reason.to_s.strip.presence || record.reason)
            rule_set.update!(active_version_id: record.id)
          end

          payload = {
            'rule_set_id' => rule_set.id, 'code' => rule_set.code, 'version' => record.version,
            'previous_version' => previous_version&.version, 'canary_percent' => rule_set.canary_percent
          }
          record_audit(AUDIT_VERSION_PUBLISHED, rule_set, actor, payload)
          publish_event(EVENT_VERSION_PUBLISHED, payload)

          success(record)
        end

        # 金丝雀：percent = 0 关闭；> 0 时必须是已发布版本且属于该规则集
        def set_canary(rule_set:, percent:, version: nil, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          value = begin
            Integer(percent)
          rescue ArgumentError, TypeError
            nil
          end
          return failure(nil, "Canary percent must be an integer between #{MIN_PERCENT} and #{MAX_PERCENT}") if value.nil?
          unless value.between?(MIN_PERCENT, MAX_PERCENT)
            return failure(nil, "Canary percent must be between #{MIN_PERCENT} and #{MAX_PERCENT}")
          end

          if value.zero?
            rule_set.update!(canary_version_id: nil, canary_percent: 0)
            record_audit(AUDIT_CANARY_UPDATED, rule_set, actor, percent: 0, version: nil)
            return success(rule_set)
          end

          record = resolve_version(rule_set, version)
          return failure(nil, 'Canary requires a published version of this rule set') if record.nil? || !record.published?

          rule_set.update!(canary_version_id: record.id, canary_percent: value)
          record_audit(AUDIT_CANARY_UPDATED, rule_set, actor, percent: value, version: record.version)
          success(rule_set)
        end

        # 回滚：以历史版本内容生成**新版本**并生效（历史不可改写）
        def rollback(rule_set:, to_version:, reason:, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          reason = reason.to_s.strip
          return failure(nil, 'Reason is required to roll back a rule version') if reason.blank?

          source = resolve_version(rule_set, to_version)
          return failure(nil, 'Version not found for this rule set') if source.nil?
          return failure(nil, 'Cannot roll back to a draft version') if source.draft?

          previous_version = rule_set.active_version
          record = nil
          ActiveRecord::Base.transaction do
            record = rule_set.versions.create!(
              version: next_version(rule_set),
              state: 'published',
              rules: source.rules,
              reason: reason,
              source_version: source.version,
              rolled_back: true,
              published_at: Time.current,
              created_by: creator_for(actor)
            )
            archive_other(rule_set, record)
            rule_set.update!(active_version_id: record.id)
          end

          payload = {
            'rule_set_id' => rule_set.id, 'code' => rule_set.code, 'version' => record.version,
            'previous_version' => previous_version&.version, 'source_version' => source.version,
            'reason' => reason
          }
          record_audit(AUDIT_VERSION_ROLLED_BACK, rule_set, actor, payload)
          publish_event(EVENT_VERSION_ROLLED_BACK, payload)

          success(record)
        end

        def activate(rule_set:, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          rule_set.update!(status: 'active')
          record_audit(AUDIT_SET_ACTIVATED, rule_set, actor, status: 'active')
          success(rule_set)
        end

        def deactivate(rule_set:, actor: nil)
          return failure(nil, 'Rule set is required') if rule_set.nil?

          rule_set.update!(status: 'inactive')
          record_audit(AUDIT_SET_DEACTIVATED, rule_set, actor, status: 'inactive')
          success(rule_set)
        end

        private

        def next_version(rule_set)
          (rule_set.versions.maximum(:version) || 0) + 1
        end

        # actor 归一：只有真正的记录才落到多态列；`'admin'` / `{type:, id:, label:}` 这类
        # 描述性 actor 交给审计（审计是权威留痕），避免多态赋值把字符串当类型。
        def creator_for(actor)
          actor if actor.is_a?(ActiveRecord::Base)
        end

        # 允许传版本记录或版本号
        def resolve_version(rule_set, version)
          return nil if version.nil?
          return version if version.is_a?(PallasTrade::RiskRuleVersion)

          rule_set.versions.find_by(version: version.to_i)
        end

        # 归档「除 keep 之外的其它 published 版本」（生效版唯一）
        def archive_other(rule_set, keep)
          rule_set.versions.where(state: 'published').where.not(id: keep.id)
                 .update_all(state: 'archived', updated_at: Time.current)
        end

        def record_audit(action, rule_set, actor, payload)
          PallasTrade::Audit.record(
            action: action,
            actor: actor.presence || 'system',
            resource: rule_set,
            after: payload
          )
        rescue StandardError => e
          Rails.logger.error("[Risk::Rules::Versioning] audit failed: #{e.class} #{e.message}")
        end

        def publish_event(event_name, payload)
          return unless PallasTrade::Events.respond_to?(:enabled?) && PallasTrade::Events.enabled?

          PallasTrade::Events.publish(event_name, payload)
        rescue StandardError => e
          Rails.logger.error("[Risk::Rules::Versioning] event publish failed: #{e.class} #{e.message}")
        end
      end
    end
  end
end
