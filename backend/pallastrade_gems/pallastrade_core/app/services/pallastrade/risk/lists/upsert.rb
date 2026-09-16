# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3）——
# `Risk::Lists::Upsert` —— 名单行的**人工维护入口**（新增 / 续期 / 撤销），幂等。
#
# 语义：
#   * 身份 = `(list_type, subject_type, value_hash)`（归一化）→ 重复维护**更新原行**，不产生第二行；
#   * 撤销 = `status = 'revoked'`（**保留历史**，不物理删除）；复维护（`revoke: false`）即复活为 `active`；
#   * 每次维护写审计 `risk_list_entry_changed`（before/after，值只落**脱敏**摘要）；
#   * 铁律：名单是运营事实 —— 不阻断流程、不调 provider、零资金副作用。
module PallasTrade
  module Risk
    module Lists
      class Upsert
        prepend PallasTrade::ServiceModule::Base

        # @param list_type [String] denylist / allowlist
        # @param subject_type [String] email / bin / ip / card_fingerprint / device / customer / address / country
        # @param value [String] 主体值（会按 subject_type 归一化）
        # @param store [PallasTrade::Store, nil] nil = 全局名单
        # @param expires_at [String, Time, nil] 可空 = 永不过期
        # @param reason [String, nil]
        # @param actor [Object, String, nil]
        # @param revoke [Boolean] true = 撤销该行
        # @return [PallasTrade::ServiceModule::Result] success(PaymentRiskList) / failure(nil, message)
        def call(list_type:, subject_type:, value:, store: nil, expires_at: nil, reason: nil, actor: nil, revoke: false)
          list_type = list_type.to_s
          subject_type = subject_type.to_s
          return failure(nil, 'Unsupported list_type') unless PallasTrade::PaymentRiskList::LIST_TYPES.include?(list_type)
          return failure(nil, 'Unsupported subject_type') unless PallasTrade::PaymentRiskList::SUBJECT_TYPES.include?(subject_type)

          normalized = PallasTrade::PaymentRiskList.normalize_value(subject_type, value)
          return failure(nil, 'Value is required') if normalized.blank?

          parsed_expiry = parse_time(expires_at)
          return failure(nil, 'Invalid expires_at') if parsed_expiry == :invalid

          entry = find_or_initialize(list_type, subject_type, value)
          before = snapshot(entry)

          entry.assign_attributes(
            store_id: store&.id,
            value: normalized,
            status: revoke ? 'revoked' : 'active',
            expires_at: parsed_expiry,
            reason: reason.presence,
            metadata: (entry.metadata || {}).merge('updated_by' => actor_label(actor))
          )
          entry.added_by = actor if entry.new_record? && actor.respond_to?(:id)
          entry.metadata['created_by'] = actor_label(actor) if entry.new_record?

          entry.save!

          PallasTrade::Audit.record(
            action: 'risk_list_entry_changed',
            actor: actor,
            resource: entry,
            before: before,
            after: snapshot(entry)
          )

          success(entry)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          failure(nil, error_message(e))
        end

        private

        def find_or_initialize(list_type, subject_type, value)
          hash = PallasTrade::PaymentRiskList.value_hash_for(list_type: list_type, subject_type: subject_type, value: value)
          PallasTrade::PaymentRiskList.find_or_initialize_by(list_type: list_type, subject_type: subject_type,
                                                             value_hash: hash)
        end

        # 审计快照：**只落脱敏值**（不落明文），并给出身份与状态
        def snapshot(entry)
          return {} if entry.nil?

          {
            list_type: entry.list_type,
            subject_type: entry.subject_type,
            masked_value: entry.value.present? ? entry.masked_value : nil,
            value_hash_prefix: entry.value_hash.present? ? entry.value_hash[0, 12] : nil,
            store_id: entry.store_id,
            status: entry.status,
            expires_at: entry.expires_at&.iso8601,
            reason: entry.reason
          }
        end

        def parse_time(raw)
          return nil if raw.nil? || raw.to_s.strip.blank?
          return raw if raw.is_a?(Time) || raw.is_a?(DateTime)
          return raw.to_time if raw.respond_to?(:to_time) && !raw.is_a?(String)

          text = raw.to_s.strip
          return text.in_time_zone if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          Time.zone.parse(text)
        rescue StandardError
          :invalid
        end

        def actor_label(actor)
          case actor
          when nil then 'system'
          when String, Symbol then actor.to_s
          else actor.respond_to?(:email) ? actor.email : actor.class.name
          end
        end

        def error_message(error)
          if error.is_a?(ActiveRecord::RecordInvalid)
            error.record.errors.full_messages.join(', ')
          else
            'Duplicate entry'
          end
        end
      end
    end
  end
end
