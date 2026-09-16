# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# `Reconciliations::Payouts::ImportCSV` —— provider 结算报表（CSV）→ 结算台账的**唯一写入口**。
#
# 命名注意：Rails 将 `CSV` 注册为 acronym，Zeitwerk 期望 `import_csv.rb` 定义 `ImportCSV`
# （不是 `ImportCsv`）—— 改写时不要“纠正”大小写。
#
# 语义：
#   * 必需列：`payout_reference`（批次号）、`kind`（charge/refund/fee/adjustment）、
#     `provider_reference`（charge/refund 单号）、`gross`；可选列：`fee`（默认 0）、
#     `net`（默认 gross − fee）、`currency`、`arrived_on`（到账日 → settled_at）、
#     `period_start` / `period_end`（结日区间）。
#   * 幂等：payout 键 `(store, provider, reference)`；行键 `(payout, provider_reference, kind)`；
#     重复导入同一文件 → 行计入 `lines_skipped`，不重复建行。
#   * 行级错误**收集不中断**（`errors: [{row:, message:}]`）；缺列 / 空文件 → 失败且不落库。
#   * 铁律：**零资金副作用** —— 只写 `pallastrade_payouts*` + `AuditLog`；绝不触碰 Payment/Refund/
#     Journal/Order/库存，也不调 provider。
module PallasTrade
  module Reconciliations
    module Payouts
      class ImportCSV
        prepend PallasTrade::ServiceModule::Base

        REQUIRED_COLUMNS = %w[payout_reference kind provider_reference gross].freeze
        OPTIONAL_COLUMNS = %w[fee net currency arrived_on period_start period_end].freeze
        DATE_COLUMNS = %w[arrived_on period_start period_end].freeze
        # 上传大小上界（字符）；超出直接拒绝（防御性，解析前判断）
        MAX_BYTES = 5.megabytes

        # @param store [PallasTrade::Store]
        # @param provider [String] provider api_type（如 'stripe'）
        # @param csv [String] CSV 文本（含表头）
        # @param source [String, nil] 来源标识（文件名/人工粘贴）
        # @param actor [Object, nil]
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success({ payouts:, lines_created:, lines_skipped:, errors: })
        def call(store:, provider:, csv:, source: nil, actor: nil, now: Time.current)
          return failure(nil, 'Store not found') if store.nil?
          return failure(nil, 'Provider is required') if provider.to_s.strip.blank?
          return failure(nil, 'CSV is empty') if csv.to_s.strip.blank?
          return failure(nil, 'CSV is too large') if csv.to_s.bytesize > MAX_BYTES

          table = ::CSV.parse(csv.to_s, headers: true, liberal_parsing: true)
          headers = table.headers.compact.map(&:to_s)
          missing = REQUIRED_COLUMNS - headers
          return failure(nil, "Missing columns: #{missing.join(', ')}") if missing.any?
          return failure(nil, 'CSV has no data rows') if table.empty?

          imported = []
          lines_created = 0
          lines_skipped = 0
          errors = []

          grouped_rows(table, errors).each do |reference, group|
            payout = upsert_payout(store, provider, reference, group, source, now)
            group[:rows].each do |row|
              created = upsert_line(payout, row, errors)
              created ? lines_created += 1 : lines_skipped += 1
            end
            payout.recalculate_totals!
            payout.refresh_status!
            imported << payout.id
          end

          record_audit(store, provider, imported, lines_created, lines_skipped, errors, actor)

          success({
            payouts: imported,
            lines_created: lines_created,
            lines_skipped: lines_skipped,
            errors: errors
          })
        rescue ::CSV::MalformedCSVError => e
          failure(nil, "Malformed CSV: #{e.message.to_s.truncate(200)}")
        end

        private

        # 按 payout_reference 分组（保持出现顺序；rows 支持 each_with_index → 行号 = index + 2）。
        def grouped_rows(rows, errors)
          groups = {}

          rows.each_with_index do |row, index|
            line_number = index + 2 # 表头占第 1 行
            reference = row['payout_reference'].to_s.strip
            if reference.blank?
              errors << { row: line_number, message: 'payout_reference is required' }
              next
            end

            kind = row['kind'].to_s.strip.downcase
            unless PallasTrade::PayoutLine::KINDS.include?(kind)
              errors << { row: line_number, message: "unsupported kind: #{row['kind'].to_s.strip}" }
              next
            end

            provider_reference = row['provider_reference'].to_s.strip
            if provider_reference.blank?
              errors << { row: line_number, message: 'provider_reference is required' }
              next
            end

            amounts = parse_amounts(row, line_number, errors)
            next if amounts.nil?

            group = groups[reference] ||= { rows: [], currency: nil, period_start: nil, period_end: nil, arrived_on: nil }
            group[:currency] ||= row['currency'].to_s.strip.presence
            DATE_COLUMNS.each do |column|
              parsed = parse_date(row[column], line_number, column, errors)
              next if parsed.nil?

              group[:arrived_on] ||= parsed if column == 'arrived_on'
              group[column.to_sym] = [group[column.to_sym], parsed].compact.max if %w[period_start period_end].include?(column)
            end
            group[:rows] << {
              kind: kind,
              provider_reference: provider_reference,
              currency: row['currency'].to_s.strip.presence,
              **amounts,
              raw: row.to_h.stringify_keys
            }
          end

          groups
        end

        def parse_amounts(row, line_number, errors)
          gross = parse_decimal(row['gross'])
          if gross.nil?
            errors << { row: line_number, message: "gross must be a number: #{row['gross'].to_s.strip}" }
            return nil
          end

          fee = parse_decimal(row['fee']) || BigDecimal('0')
          net = parse_decimal(row['net']) || (gross - fee)

          { gross_amount: gross, fee_amount: fee, net_amount: net }
        end

        def parse_decimal(value)
          text = value.to_s.strip.delete(',').delete(' ')
          return nil if text.blank?

          BigDecimal(text)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_date(value, line_number, column, errors)
          text = value.to_s.strip
          return nil if text.blank?

          Date.parse(text)
        rescue ArgumentError, TypeError
          errors << { row: line_number, message: "#{column} is not a date: #{text}" }
          nil
        end

        # 幂等：同 (store, provider, reference) 的批次复用既有行，只更新导入元数据。
        def upsert_payout(store, provider, reference, group, source, now)
          payout = PallasTrade::Payout.find_or_initialize_by(
            store_id: store.id, provider: provider.to_s, reference: reference
          )

          payout.assign_attributes(
            currency: group[:currency] || payout.currency || store.default_currency&.to_s,
            period_start: group[:period_start] || payout.period_start,
            period_end: group[:period_end] || payout.period_end,
            settled_at: group[:arrived_on] ? group[:arrived_on].in_time_zone.beginning_of_day : payout.settled_at,
            imported_at: now,
            import_source: source.to_s.presence || payout.import_source,
            status: payout.status.presence || 'in_transit',
            metadata: (payout.metadata || {}).merge('last_import_row_count' => group[:rows].size)
          )
          payout.save!
          payout
        end

        # @return [Boolean] true = 新建；false = 已存在（计入 skipped）
        def upsert_line(payout, row, _errors)
          line = PallasTrade::PayoutLine.find_or_initialize_by(
            payout_id: payout.id, provider_reference: row[:provider_reference], kind: row[:kind]
          )
          created = line.new_record?

          line.assign_attributes(
            currency: row[:currency] || payout.currency,
            gross_amount: row[:gross_amount],
            fee_amount: row[:fee_amount],
            net_amount: row[:net_amount],
            raw: row[:raw]
          )
          line.match_status = 'pending' if line.match_status.blank?
          line.save!
          created
        end

        def record_audit(store, provider, payout_ids, lines_created, lines_skipped, errors, actor)
          PallasTrade::Audit.record(
            actor: actor.presence || 'system',
            action: 'payouts_imported',
            resource: store,
            metadata: {
              provider: provider.to_s,
              payouts: payout_ids,
              lines_created: lines_created,
              lines_skipped: lines_skipped,
              errors: errors.size
            }
          )
        end
      end
    end
  end
end
