# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 报表）——
# `Payments::Costs::Report` —— **支付成本报表**（只读聚合）：
#   * 统计域：本店 + 已完成支付（`Payment.completed`）+ 支付创建时间 `[from, to)`（左闭右开）；
#   * 汇总：`gross / fee / net / fee_rate / 单均成本（按订单去重）/ 订单数 / 支付笔数 / 未定价笔数`；
#   * 维度：**入口**（`payment_method` × `method_key`，当前映射口径）、provider、币种；
#   * 下钻：`detail` 给出逐笔支付（有界，超出标记 `truncated`）；
#   * 实际 vs 模型：并列结算台账 `payout_lines.fee_amount`（D13b）作为 `actual_fee` 与偏差。
#
# 铁律：**零写库、零 provider I/O**；报表任何数字都可在 `detail` 中复现（自洽断言见 spec）。
module PallasTrade
  module Payments
    module Costs
      class Report
        prepend PallasTrade::ServiceModule::Base

        DEFAULT_PERIOD_DAYS = 30
        MAX_RANGE_DAYS = 366
        DETAIL_LIMIT = 500
        MAX_PAYMENTS = 20_000
        UNKNOWN_PROVIDER = 'unknown'

        # @param store [PallasTrade::Store]
        # @param from [Time, String, nil]
        # @param to [Time, String, nil]
        # @param payment_method_id [Integer, String, nil]
        # @param currency [String, nil]
        # @param method_key [String, nil]
        # @param limit [Integer]
        # @return [PallasTrade::ServiceModule::Result] success(Hash)
        def call(store:, from: nil, to: nil, payment_method_id: nil, currency: nil, method_key: nil,
                 limit: DETAIL_LIMIT, now: Time.current)
          return failure(nil, 'Store is required') if store.nil?

          period = normalize_period(from, to, now)
          policies = load_policies(store, period[:to], period[:clamped])
          needs_region = policies.any? { |policy| policy.region.present? || policy.home_country.present? }
          needs_card_type = policies.any? { |policy| policy.card_type.present? }

          payments = load_payments(store, period, payment_method_id, currency, needs_region, needs_card_type)
          truncated = payments.size >= MAX_PAYMENTS
          payments = payments.first(MAX_PAYMENTS)

          actual_fees = load_actual_fees(payments)
          rows = payments.map { |payment| build_row(payment, policies, actual_fees, needs_region, needs_card_type, store) }
          rows = rows.select { |row| row[:method_key].to_s == method_key.to_s } if method_key.present?

          detail = rows.first(limit.to_i.positive? ? limit.to_i : DETAIL_LIMIT)

          success({
                    period: period,
                    totals: totals_for(rows),
                    by_entry: group_rows(rows, :entry_key, entry_labels(rows)),
                    by_provider: group_rows(rows, :provider_key, provider_labels(rows)),
                    by_currency: group_rows(rows, :currency, {}),
                    detail: detail,
                    detail_truncated: rows.size > detail.size,
                    unpriced_reasons: unpriced_reasons(rows),
                    policies_considered: policies.size,
                    payments_scanned: payments.size,
                    truncated: truncated,
                    filters: {
                      payment_method_id: payment_method_id.presence,
                      currency: currency.to_s.upcase.presence,
                      method_key: method_key.presence
                    },
                    generated_at: now
                  })
        end

        private

        def normalize_period(from, to, now)
          to_time = parse_time(to) || now
          from_time = parse_time(from) || (to_time - DEFAULT_PERIOD_DAYS.days)
          clamped = false

          if from_time > to_time
            from_time, to_time = to_time, from_time
          end

          if (to_time - from_time) > MAX_RANGE_DAYS.days
            from_time = to_time - MAX_RANGE_DAYS.days
            clamped = true
          end

          { from: from_time, to: to_time, days: ((to_time - from_time) / 1.day).round, clamped: clamped }
        end

        def parse_time(value)
          return nil if value.blank?
          return value if value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def load_policies(store, at, _clamped)
          PallasTrade::PaymentFeePolicy.for_store(store).active.effective_at(at).by_priority.to_a
        end

        def load_payments(store, period, payment_method_id, currency, needs_region, needs_card_type)
          order_ids = PallasTrade::Order.where(store_id: store.id)
          order_ids = order_ids.where(currency: currency.to_s.upcase) if currency.present?

          # 用子查询而非 `joins(:order)`：`joins` 与 `includes(order:)` 同用时预加载会被丢弃（→ 每笔支付一次查询的 N+1）
          scope = PallasTrade::Payment.completed
                                        .where(order_id: order_ids)
                                        .where('pallastrade_payments.created_at >= ? AND pallastrade_payments.created_at < ?',
                                               period[:from], period[:to])
          scope = scope.where(payment_method_id: payment_method_id) if payment_method_id.present?

          includes = [:payment_method]
          includes << :source if needs_card_type
          scope = if needs_region
                    scope.includes(*includes, order: { bill_address: :country })
                  else
                    scope.includes(*includes, :order)
                  end

          scope.order('pallastrade_payments.created_at ASC, pallastrade_payments.id ASC').limit(MAX_PAYMENTS + 1).to_a
        end

        # 结算台账实际扣费：**单次查询**建索引（payment_id → Σ fee_amount），避免 N+1
        def load_actual_fees(payments)
          ids = payments.map(&:id).compact
          return {} if ids.empty?

          PallasTrade::PayoutLine.where(payment_id: ids, refund_id: nil)
                                 .group(:payment_id)
                                 .sum(:fee_amount)
        end

        def build_row(payment, policies, actual_fees, needs_region, needs_card_type, store)
          context = PallasTrade::Payments::Fees::Resolver::Context.from_payment(
            payment, with_region: needs_region, with_card_type: needs_card_type
          )
          # 报表已持有店铺对象：显式注入（否则逐笔解析 order.store → N+1）
          context.store = store
          resolution = PallasTrade::Payments::Fees::Resolver.call(
            context: context, at: payment.created_at, candidates: policies
          )
          policy = resolution.value[:policy]

          outcome = PallasTrade::Payments::Fees::Calculate.call(
            amount: payment.amount,
            currency: context.currency,
            policy: policy,
            order_country: context.order_country
          ).value

          method_key = context.method_key.presence
          provider_key = (payment.payment_method_id || UNKNOWN_PROVIDER).to_s
          actual_fee = actual_fees[payment.id]

          {
            payment_id: payment.id,
            number: payment.number,
            order_id: payment.order_id,
            order_number: payment.order&.number,
            order_currency: context.currency,
            paid_at: payment.created_at,
            provider_key: provider_key,
            provider_label: provider_label(payment),
            method_key: method_key,
            entry_key: "#{provider_key}:#{method_key || 'default'}",
            entry_label: entry_label(payment, method_key),
            amount: outcome[:amount],
            fee_amount: outcome[:total_fee],
            net_amount: outcome[:net_amount],
            percent_fee: outcome[:percent_fee],
            platform_fee: outcome[:platform_fee],
            cross_border_fee: outcome[:cross_border_fee],
            conversion_fee: outcome[:conversion_fee],
            adjustment: outcome[:adjustment],
            fixed_fee: outcome[:fixed_fee],
            priced: outcome[:priced],
            policy_id: outcome[:policy_id],
            policy_name: outcome[:policy_name],
            cross_border: outcome[:cross_border],
            converted: outcome[:converted],
            signals: (resolution.value[:signals] + outcome[:signals]).uniq,
            actual_fee_amount: actual_fee.present? ? actual_fee.to_d.round(2) : nil,
            variance_amount: actual_fee.present? ? (actual_fee.to_d.round(2) - outcome[:total_fee]) : nil
          }
        end

        def provider_label(payment)
          method = payment.respond_to?(:payment_method) ? payment.payment_method : nil
          method&.name.presence || UNKNOWN_PROVIDER
        end

        def entry_label(payment, method_key)
          method = payment.respond_to?(:payment_method) ? payment.payment_method : nil
          return UNKNOWN_PROVIDER if method.nil?

          if method_key.present? && method.respond_to?(:option_display_name)
            name = method.option_display_name(method_key)
            return name if name.present? && name != method.name
          end

          method.name.presence || UNKNOWN_PROVIDER
        rescue StandardError
          method&.name.presence || UNKNOWN_PROVIDER
        end

        def entry_labels(rows)
          rows.each_with_object({}) { |row, acc| acc[row[:entry_key]] ||= row[:entry_label] }
        end

        def provider_labels(rows)
          rows.each_with_object({}) { |row, acc| acc[row[:provider_key]] ||= row[:provider_label] }
        end

        def totals_for(rows)
          gross = sum(rows, :amount)
          fee = sum(rows, :fee_amount)
          net = sum(rows, :net_amount)
          order_count = rows.map { |row| row[:order_id] }.compact.uniq.size
          payment_count = rows.size
          actual_rows = rows.select { |row| row[:actual_fee_amount].present? }
          actual_fee = sum(actual_rows, :actual_fee_amount)
          variance = sum(actual_rows, :variance_amount)

          {
            gross_amount: gross,
            fee_amount: fee,
            net_amount: net,
            fee_rate: rate(fee, gross),
            order_count: order_count,
            payment_count: payment_count,
            priced_count: rows.count { |row| row[:priced] },
            unpriced_count: rows.count { |row| !row[:priced] },
            average_order_cost: order_count.positive? ? (fee / order_count).round(2) : 0.to_d,
            average_payment_cost: payment_count.positive? ? (fee / payment_count).round(2) : 0.to_d,
            actual_fee_amount: actual_fee,
            variance_amount: variance,
            variance_rate: rate(variance, actual_fee),
            variance_coverage: actual_rows.size
          }
        end

        # @param rows [Array<Hash>]
        # @param key [Symbol]
        # @param labels [Hash]
        def group_rows(rows, key, labels)
          grouped = rows.group_by { |row| row[key] }
          grouped.map do |group_key, group|
            gross = sum(group, :amount)
            fee = sum(group, :fee_amount)
            order_count = group.map { |row| row[:order_id] }.compact.uniq.size
            actual_rows = group.select { |row| row[:actual_fee_amount].present? }
            actual_fee = sum(actual_rows, :actual_fee_amount)

            {
              key: group_key.to_s,
              label: labels[group_key].presence || group.first[:provider_label],
              method_key: group.first[:method_key],
              provider_id: group.first[:provider_key],
              payment_count: group.size,
              order_count: order_count,
              gross_amount: gross,
              fee_amount: fee,
              net_amount: sum(group, :net_amount),
              fee_rate: rate(fee, gross),
              average_order_cost: order_count.positive? ? (fee / order_count).round(2) : 0.to_d,
              actual_fee_amount: actual_fee,
              variance_amount: sum(actual_rows, :variance_amount),
              unpriced_count: group.count { |row| !row[:priced] }
            }
          end.sort_by { |group| [-group[:fee_amount].to_d, group[:key]] }
        end

        def unpriced_reasons(rows)
          rows.reject { |row| row[:priced] }
              .flat_map { |row| row[:signals].presence || ['unknown'] }
              .tally
              .sort_by { |_reason, count| -count }
              .to_h
        end

        def sum(rows, key)
          rows.sum { |row| row[key].to_d }.round(2)
        end

        def rate(part, whole)
          return 0.to_d if whole.to_d.zero?

          (part.to_d / whole.to_d * 100).round(4)
        end
      end
    end
  end
end
