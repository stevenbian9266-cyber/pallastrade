# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 批量导入）——
# `Risk::Lists::ImportCSV` —— 名单的**批量导入入口**（粘贴文本或上传文件内容）。
#
# 命名注意：Rails 将 `CSV` 注册为 acronym，Zeitwerk 期望 `import_csv.rb` 定义 `ImportCSV`
# （不是 `ImportCsv`）—— 不要「纠正」大小写；`PallasTrade` 命名空间内必须写 `::CSV`。
#
# 语义：
#   * 必需列：`list_type`（denylist/allowlist）、`subject_type`、`value`；可选列：`expires_at`、`reason`；
#   * 幂等：身份 = 归一化后的 `(list_type, subject_type, value_hash)` → 重复导入同一文件 `created: 0`；
#     已有行按新 `expires_at` / `reason` **续期更新**（计入 `updated`），并复活为 `active`；
#   * 行级错误**收集不中断**（`errors: [{ row:, message: }]`）；缺列 / 空文件 / 超大 → 失败且不落库；
#   * 铁律：零资金副作用、零 provider；审计只记计数（含脱敏样例上限）。
module PallasTrade
  module Risk
    module Lists
      class ImportCSV
        prepend PallasTrade::ServiceModule::Base

        REQUIRED_COLUMNS = %w[list_type subject_type value].freeze
        OPTIONAL_COLUMNS = %w[expires_at reason].freeze
        # 上传大小上界（5MB）：解析前拒绝（防御性）
        MAX_BYTES = 5.megabytes
        # 审计里保留的脱敏样例条数（避免审计膨胀）
        AUDIT_SAMPLE_LIMIT = 5

        # @param store [PallasTrade::Store, nil] nil = 全局名单
        # @param csv [String] CSV 文本（含表头）
        # @param actor [Object, nil]
        # @param source [String, nil] 来源标识（文件名 / 人工粘贴）
        # @return [PallasTrade::ServiceModule::Result] success({ created:, updated:, errors:, entries: })
        def call(csv:, store: nil, actor: nil, source: nil)
          return failure(nil, 'CSV is empty') if csv.to_s.strip.blank?
          return failure(nil, 'CSV is too large') if csv.to_s.bytesize > MAX_BYTES

          table = ::CSV.parse(csv.to_s, headers: true, liberal_parsing: true)
          headers = table.headers.compact.map(&:to_s)
          missing = REQUIRED_COLUMNS - headers
          return failure(nil, "Missing columns: #{missing.join(', ')}") if missing.any?
          return failure(nil, 'CSV has no data rows') if table.empty?

          created = 0
          updated = 0
          errors = []
          samples = []

          table.each_with_index do |row, index|
            line_number = index + 2 # 表头占第 1 行
            attrs = attributes_for(row, line_number, errors)
            next if attrs.nil?

            entry = upsert_entry(attrs, store, actor, errors, line_number)
            next if entry.nil?

            entry.previously_new_record? ? created += 1 : updated += 1
            samples << { 'subject_type' => entry.subject_type, 'masked' => entry.masked_value } if samples.size < AUDIT_SAMPLE_LIMIT
          end

          record_audit(created, updated, errors, samples, actor, store, source)

          success({ created: created, updated: updated, errors: errors, samples: samples })
        rescue ::CSV::MalformedCSVError => e
          failure(nil, "Malformed CSV: #{e.message.to_s[0, 200]}")
        end

        private

        # @return [Hash, nil] nil = 该行有错（已收集）
        def attributes_for(row, line_number, errors)
          list_type = row['list_type'].to_s.strip.downcase
          unless PallasTrade::PaymentRiskList::LIST_TYPES.include?(list_type)
            errors << { row: line_number, message: "unsupported list_type: #{row['list_type'].to_s.strip}" }
            return nil
          end

          subject_type = row['subject_type'].to_s.strip.downcase
          unless PallasTrade::PaymentRiskList::SUBJECT_TYPES.include?(subject_type)
            errors << { row: line_number, message: "unsupported subject_type: #{row['subject_type'].to_s.strip}" }
            return nil
          end

          value = PallasTrade::PaymentRiskList.normalize_value(subject_type, row['value'])
          if value.blank?
            errors << { row: line_number, message: 'value is required' }
            return nil
          end

          expires_at = parse_expiry(row['expires_at'])
          if expires_at == :invalid
            errors << { row: line_number, message: "invalid expires_at: #{row['expires_at'].to_s.strip}" }
            return nil
          end

          {
            list_type: list_type,
            subject_type: subject_type,
            value: value,
            expires_at: expires_at,
            reason: row['reason'].to_s.strip.presence
          }
        end

        def upsert_entry(attrs, store, actor, errors, line_number)
          hash = PallasTrade::PaymentRiskList.value_hash_for(
            list_type: attrs[:list_type], subject_type: attrs[:subject_type], value: attrs[:value]
          )
          entry = PallasTrade::PaymentRiskList.find_or_initialize_by(
            list_type: attrs[:list_type], subject_type: attrs[:subject_type], value_hash: hash
          )
          new_record = entry.new_record?
          entry.assign_attributes(
            store_id: store&.id,
            value: attrs[:value],
            status: 'active',
            expires_at: attrs[:expires_at],
            reason: attrs[:reason].presence || entry.reason,
            metadata: (entry.metadata || {}).merge('imported_by' => actor_label(actor))
          )
          entry.added_by = actor if new_record && actor.respond_to?(:id)
          entry.metadata['created_by'] = actor_label(actor) if new_record
          entry.save!
          entry
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          errors << { row: line_number, message: e.respond_to?(:record) ? e.record.errors.full_messages.join(', ') : 'duplicate entry' }
          nil
        end

        def parse_expiry(raw)
          text = raw.to_s.strip
          return nil if text.blank?
          return text.in_time_zone if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          Time.zone.parse(text)
        rescue StandardError
          :invalid
        end

        # 审计：只记计数 + 脱敏样例（**不落明文**）
        def record_audit(created, updated, errors, samples, actor, store, source)
          PallasTrade::Audit.record(
            action: 'risk_list_imported',
            actor: actor,
            resource: store,
            after: {
              created: created,
              updated: updated,
              errors_count: errors.size,
              samples: samples,
              source: source.presence || 'pasted'
            },
            metadata: { 'errors' => errors.first(5) }
          )
        rescue StandardError => e
          Rails.logger.error("[Risk::Lists::ImportCSV] audit failed: #{e.class} #{e.message}")
        end

        def actor_label(actor)
          case actor
          when nil then 'system'
          when String, Symbol then actor.to_s
          else actor.respond_to?(:email) ? actor.email : actor.class.name
          end
        end
      end
    end
  end
end
