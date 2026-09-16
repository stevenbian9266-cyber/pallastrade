# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# `Disputes::RateReport` —— **拒付率报表**（按卡组织：笔数比 + 金额比 + 阈值位置 + 下钻）。
#
# 与既有 `Disputes::OpsReport` 的分工：OpsReport 回答「争议侧的运营质量」（胜诉率 / 时限 / 时长），
# 本服务回答「**拒付率**」——需要**分母**（交易）与**卡组织阈值**，因此独立成服务，且不改 OpsReport。
#
# 口径（唯一权威，页面 / CSV / 预警服务共用；写死在这里避免第二种解释）：
#   * 窗口：`to = 评估时刻`，`from = to - window_days`（默认 30 天，来自 `RatePolicy`）。
#   * 分子：`Dispute.for_store(store).where(created_at: 窗口)`（开案时间口径与 OpsReport 一致）。
#   * 分母：`Payment.completed`，`order_id ∈ store.orders`，按 `payment.created_at` 落窗口；
#     按卡组织判定时只计**该组织品牌**的卡支付。
#   * 卡组织：`payment.source`（`PallasTrade::CreditCard`）的 `cc_type`，归一
#     （`mastercard|maestro → master`、`amex → american_express`，与 `CreditCard#cc_type=` 同词汇）；
#     不可判定 → `unknown`（**不猜**，单独成行且**不参与**任何组织的阈值判定）。
#   * 金额比：**只统计店铺默认币种**（跨币种不混算）；其他币种的数量计入 `excluded_other_currency_*`
#     并在页面明示（**不静默丢弃**）。
#   * 比率分母为 0 → `nil`（不用 0 伪装）。
#
# 铁律：**只读**（零写库、零审计、零事件、零 provider I/O）；异常 → 降级信封（字段齐全 + degraded），
# 绝不 500；查询数**不随行数增长**（批量预加载，禁止逐行查询）。
module PallasTrade
  module Disputes
    class RateReport
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_DIMENSION = 'card_fingerprint'
      DIMENSIONS = %w[card_fingerprint country entry segment].freeze
      DEFAULT_LIMIT = 200
      MAX_LIMIT = 500
      UNKNOWN = 'unknown'
      CARD_SOURCE_TYPE = 'PallasTrade::CreditCard'
      BRAND_ALIASES = { 'mastercard' => 'master', 'maestro' => 'master', 'amex' => 'american_express' }.freeze
      SEGMENT_NEW = 'new'
      SEGMENT_RETURNING = 'returning'

      # @param store [PallasTrade::Store]
      # @param window_days [Integer, nil] 覆盖店铺策略窗口（同 RangePolicy 归一）
      # @param from [Time, String, nil]
      # @param to [Time, String, nil]
      # @param dimension [String, nil] 下钻维度（card_fingerprint / country / entry / segment）
      # @param network [String, nil] 只看某卡组织
      # @param limit [Integer, nil] 下钻桶数上限（默认 200，最大 500）
      # @return [PallasTrade::ServiceModule::Result] success(Hash)
      def call(store:, window_days: nil, from: nil, to: nil, dimension: nil, network: nil, limit: nil)
        return success(degraded_envelope('store_missing')) if store.nil?

        @store = store
        @policy = RatePolicy.for(store)
        @currency = default_currency(store)
        @dimension = normalize_dimension(dimension)
        @network_filter = network.to_s.strip.downcase.presence
        @limit = normalize_limit(limit)
        @window_days = window_days.present? ? RatePolicy.new(raw: { 'window_days' => window_days }).window_days : @policy.window_days
        @range = build_range(from, to)

        success(build_report)
      rescue StandardError => e
        success(degraded_envelope("report_unavailable:#{e.class}"))
      end

      private

      # 降级信封：字段齐全但数值为「不可用」，并说明原因 —— 不猜、不 500
      def degraded_envelope(reason)
        {
          scope: { store_id: nil, window_days: nil, from: nil, to: nil, currency: nil,
                   dimension: nil, network: nil },
          policy: { enabled: nil, warning_ratio: nil, window_days: nil, configured_networks: [] },
          totals: empty_totals,
          networks: [],
          breakdown: { dimension: nil, rows: [], truncated: false, total_rows: 0 },
          notes: [],
          degraded: [reason]
        }
      end

      def empty_totals
        { transactions_count: 0, transactions_amount: nil, disputes_count: 0, disputes_amount: nil,
          count_ratio: nil, amount_ratio: nil, currency: nil,
          unknown_network_disputes: 0, excluded_other_currency_payments: 0,
          excluded_other_currency_disputes: 0, returning_payments: 0 }
      end

      def build_report
        context = load_context
        networks = build_networks(context)
        {
          scope: {
            store_id: @store.id, window_days: @window_days, from: @range.begin, to: @range.end,
            currency: @currency, dimension: @dimension, network: @network_filter
          },
          policy: {
            enabled: @policy.enabled?, warning_ratio: @policy.warning_ratio,
            window_days: @policy.window_days, configured_networks: @policy.configured_networks
          },
          totals: build_totals(context),
          networks: networks,
          breakdown: build_breakdown(context),
          notes: notes_for(context),
          degraded: []
        }
      end

      # === 数据装载（每条最多一次查询；与行数无关）===

      # @return [Hash] 批量上下文（payments / disputes / 卡 / 订单 / 邮箱历史）
      def load_context
        payments = window_payments
        disputes = window_disputes
        dispute_payment_ids = disputes.map { |row| row[:payment_id] }.compact.uniq
        extra_payments = dispute_payment_ids.empty? ? [] : payment_rows_for(PallasTrade::Payment.where(id: dispute_payment_ids))

          all_payments = (payments + extra_payments).uniq { |row| row[:id] }
          cards = credit_card_map(all_payments)
          methods = payment_method_map(all_payments)
          orders = order_map(all_payments)
          seen_before = previously_ordered_emails(orders)

          {
            payments: all_payments,
            # 交易侧口径：**只算窗口内支付**（争议关联的窗口外支付仅用于卡组织/维度归因）
            window_payments: payments,
            payments_by_id: all_payments.index_by { |row| row[:id] },
            window_payment_ids: payments.map { |row| row[:id] }.to_set,
            disputes: disputes,
            cards: cards,
            methods: methods,
            orders: orders,
            seen_before: seen_before
          }
      end

      def window_payments
        scope = PallasTrade::Payment.completed
                                 .where(order_id: @store.orders.select(:id))
                                 .where(created_at: @range)
        payment_rows_for(scope)
      end

      def window_disputes
        PallasTrade::Dispute.for_store(@store)
                            .where(created_at: @range)
                            .pluck(:id, :payment_id, :amount, :currency)
                            .map { |id, payment_id, amount, currency| { id: id, payment_id: payment_id, amount: amount, currency: currency } }
      end

      # ⚠️ `pallastrade_payments` **没有 currency 列**：支付的币种来自其订单（`orders.currency`）
      def payment_rows_for(scope)
        scope.pluck(:id, :order_id, :payment_method_id, :source_type, :source_id, :amount)
             .map do |id, order_id, pm_id, source_type, source_id, amount|
          { id: id, order_id: order_id, payment_method_id: pm_id, source_type: source_type,
            source_id: source_id, amount: amount }
        end
      end

      # @return [Hash] card_id → { brand:, fingerprint: }
      def credit_card_map(payments)
        ids = payments.select { |row| row[:source_type] == CARD_SOURCE_TYPE }
                      .map { |row| row[:source_id] }.compact.uniq
        return {} if ids.empty?

        PallasTrade::CreditCard.where(id: ids).pluck(:id, :cc_type, :fingerprint)
                               .each_with_object({}) do |(id, cc_type, fingerprint), acc|
          acc[id] = { brand: normalize_brand(cc_type), fingerprint: fingerprint.presence }
        end
      end

      # @return [Hash] payment_method_id → 入口 kind（复用 D16 读模型，避免第二套口径）
      def payment_method_map(payments)
        ids = payments.map { |row| row[:payment_method_id] }.compact.uniq
        return {} if ids.empty?

        PallasTrade::PaymentMethod.where(id: ids).each_with_object({}) do |method, acc|
          acc[method.id] = method.effective_payment_option['kind'].to_s.presence || UNKNOWN
        end
      end

      # @return [Hash] order_id → { email:, country:, currency:, returning: }
      def order_map(payments)
        order_ids = payments.map { |row| row[:order_id] }.compact.uniq
        return {} if order_ids.empty?

        rows = PallasTrade::Order.where(id: order_ids).pluck(:id, :email, :bill_address_id, :currency)
        addresses = address_country_map(rows.map { |row| row[2] }.compact.uniq)

        rows.each_with_object({}) do |(id, email, bill_address_id, currency), acc|
          acc[id] = { email: email.to_s.downcase.presence, country: addresses[bill_address_id],
                      currency: currency.to_s.upcase.presence }
        end
      end

      # @return [Hash] address_id → ISO 国家码
      def address_country_map(address_ids)
        return {} if address_ids.empty?

        addresses = PallasTrade::Address.where(id: address_ids).pluck(:id, :country_id)
        country_ids = addresses.map { |row| row[1] }.compact.uniq
        return {} if country_ids.empty?

        countries = PallasTrade::Country.where(id: country_ids).pluck(:id, :iso).to_h
        addresses.each_with_object({}) do |(address_id, country_id), acc|
          acc[address_id] = countries[country_id].presence
        end
      end

      # 窗口开始前已下单的邮箱（客群维度：回头客 vs 新客）；一次查询
      # @return [Set<String>]
      def previously_ordered_emails(orders)
        emails = orders.values.map { |info| info[:email] }.compact.uniq
        return Set.new if emails.empty? || @range.begin.nil?

        PallasTrade::Order.where(email: emails).where(created_at: ...@range.begin).distinct.pluck(:email)
                          .map { |email| email.to_s.downcase }.to_set
      end

      # === 汇总与卡片 ===

      def build_totals(context)
        tx = tally_transactions(context)
        dp = tally_disputes(context)
        totals = empty_totals.merge(
          transactions_count: tx[:count], transactions_amount: tx[:amount],
          disputes_count: dp[:count], disputes_amount: dp[:amount],
          currency: @currency,
          unknown_network_disputes: dp[:by_network][UNKNOWN].to_i,
          excluded_other_currency_payments: tx[:excluded_currency],
          excluded_other_currency_disputes: dp[:excluded_currency],
          returning_payments: tx[:returning]
        )
        totals[:count_ratio] = ratio(dp[:count], tx[:count])
        totals[:amount_ratio] = ratio(dp[:amount], tx[:amount])
        totals
      end

      def build_networks(context)
        tx = tally_transactions(context)
        dp = tally_disputes(context)

        keys = (tx[:by_network].keys + dp[:by_network].keys).uniq.reject { |key| key == UNKNOWN && @network_filter.present? }
        keys = keys.select { |key| key == @network_filter } if @network_filter.present?

        keys.sort_by { |key| [-dp[:by_network][key].to_i, -tx[:by_network][key].to_i, key] }.map do |network|
          transactions_count = tx[:by_network][network].to_i
          disputes_count = dp[:by_network][network].to_i
          transactions_amount = tx[:by_network_amount][network]
          disputes_amount = dp[:by_network_amount][network]
          decision = @policy.classify(
            network: network,
            count_ratio: ratio(disputes_count, transactions_count),
            amount_ratio: ratio(disputes_amount, transactions_amount)
          )

          {
            network: network,
            currency: @currency,
            warning_ratio: @policy.warning_ratio,
            transactions_count: transactions_count,
            transactions_amount: transactions_amount,
            disputes_count: disputes_count,
            disputes_amount: disputes_amount,
            count_ratio: ratio(disputes_count, transactions_count),
            amount_ratio: ratio(disputes_amount, transactions_amount),
            count_ratio_bps: decision[:count_bps],
            amount_ratio_bps: decision[:amount_bps],
            count_threshold_bps: decision[:count_threshold_bps],
            amount_threshold_bps: decision[:amount_threshold_bps],
            status: decision[:status],
            triggered_metrics: decision[:triggered_metrics],
            count_usage_percent: usage_percent(decision[:count_bps], decision[:count_threshold_bps]),
            amount_usage_percent: usage_percent(decision[:amount_bps], decision[:amount_threshold_bps])
          }
        end
      end

      # 交易侧聚合（按组织 + 按币种过滤）
      def tally_transactions(context)
        @tx_tally ||= begin
          by_network = Hash.new(0)
          by_network_amount = {}
          amount = BigDecimal(0)
          excluded = 0
          returning = 0

          context[:window_payments].each do |payment|
            network = network_for_payment(payment, context)
            by_network[network] += 1
            returning += 1 if returning_email?(payment, context)
            if currency_for(payment, context) == @currency
              by_network_amount[network] = by_network_amount.fetch(network, BigDecimal(0)) + payment[:amount].to_d
              amount += payment[:amount].to_d
            else
              excluded += 1
            end
          end

          { by_network: by_network, by_network_amount: by_network_amount,
            count: context[:window_payments].size, amount: amount,
            excluded_currency: excluded, returning: returning }
        end
      end

      # 争议侧聚合（按组织 + 按币种过滤）
      def tally_disputes(context)
        @dp_tally ||= begin
          by_network = Hash.new(0)
          by_network_amount = {}
          amount = BigDecimal(0)
          excluded = 0

          context[:disputes].each do |dispute|
            payment = context[:payments_by_id][dispute[:payment_id]]
            network = payment.nil? ? UNKNOWN : network_for_payment(payment, context)
            by_network[network] += 1
            if dispute[:currency].to_s.upcase == @currency
              by_network_amount[network] = by_network_amount.fetch(network, BigDecimal(0)) + dispute[:amount].to_d
              amount += dispute[:amount].to_d
            else
              excluded += 1
            end
          end

          { by_network: by_network, by_network_amount: by_network_amount,
            count: context[:disputes].size, amount: amount, excluded_currency: excluded }
        end
      end

      # 卡组织归因：卡指纹 → 品牌；非卡 / 品牌缺失 → unknown（不猜）
      def network_for_payment(payment, context)
        return UNKNOWN unless payment[:source_type] == CARD_SOURCE_TYPE

        context[:cards][payment[:source_id]]&.[](:brand) || UNKNOWN
      end

      def returning_email?(payment, context)
        email = context[:orders][payment[:order_id]]&.[](:email)
        return false if email.blank?

        context[:seen_before].include?(email)
      end

      # 支付币种：来自订单（`payments` 无 currency 列）
      # @return [String, nil]
      def currency_for(payment, context)
        context[:orders][payment[:order_id]]&.[](:currency) || @currency
      end

      # === 下钻 ===

      def build_breakdown(context)
        rows = breakdown_rows(context)
        total_disputes = context[:disputes].size
        total_dispute_amount = amount_in_currency(context)

        enriched = rows.map do |row|
          row.merge(
            dispute_share: ratio(row[:disputes_count], total_disputes),
            amount_share: ratio(row[:disputes_amount], total_dispute_amount)
          )
        end

        sorted = enriched.sort_by { |row| [-row[:disputes_count].to_i, -row[:transactions_count].to_i, row[:key].to_s] }
        limited = sorted.first(@limit)

        {
          dimension: @dimension,
          rows: limited,
          truncated: sorted.size > limited.size,
          total_rows: sorted.size
        }
      end

      def breakdown_rows(context)
        buckets = Hash.new do |hash, key|
          hash[key] = { key: key, transactions_count: 0, transactions_amount: BigDecimal(0),
                        disputes_count: 0, disputes_amount: BigDecimal(0) }
        end

        context[:window_payments].each do |payment|
          key = bucket_key_for_transaction(payment, context)
          bucket = buckets[key]
          bucket[:transactions_count] += 1
          bucket[:transactions_amount] += payment[:amount].to_d if currency_for(payment, context) == @currency
        end

        context[:disputes].each do |dispute|
          payment = context[:payments_by_id][dispute[:payment_id]]
          key = payment.nil? ? UNKNOWN : bucket_key_for_transaction(payment, context)
          bucket = buckets[key]
          bucket[:disputes_count] += 1
          bucket[:disputes_amount] += dispute[:amount].to_d if dispute[:currency].to_s.upcase == @currency
        end

        buckets.values
      end

      # 桶键（四维度；不可判定 → unknown，不丢弃）
      def bucket_key_for_transaction(payment, context)
        case @dimension
        when 'country'
          context[:orders][payment[:order_id]]&.[](:country).presence || UNKNOWN
        when 'entry'
          context[:methods][payment[:payment_method_id]].presence || UNKNOWN
        when 'segment'
          returning_email?(payment, context) ? SEGMENT_RETURNING : SEGMENT_NEW
        else
          fingerprint = context[:cards][payment[:source_id]]&.[](:fingerprint)
          fingerprint.presence || UNKNOWN
        end
      end

      def notes_for(context)
        notes = ['bin_unavailable', 'combination_payments_excluded']
        notes << 'other_currency_excluded' if tally_transactions(context)[:excluded_currency].positive? ||
                                              tally_disputes(context)[:excluded_currency].positive?
        notes << 'unconfigured_networks' if @policy.configured_networks.empty?
        notes
      end

      # === 小工具 ===

      def usage_percent(observed_bps, threshold_bps)
        return nil if observed_bps.nil? || threshold_bps.nil? || threshold_bps.to_i <= 0

        (observed_bps.to_d / threshold_bps.to_d * 100).round(1)
      end

      def ratio(numerator, denominator)
        return nil if denominator.nil? || denominator.to_d <= 0

        (numerator.to_d / denominator.to_d).round(6)
      end

      def amount_in_currency(context)
        context[:disputes].sum { |row| row[:currency].to_s.upcase == @currency ? row[:amount].to_d : BigDecimal(0) }
      end

      def normalize_brand(cc_type)
        brand = cc_type.to_s.strip.downcase
        return nil if brand.blank?

        BRAND_ALIASES[brand] || brand
      end

      def default_currency(store)
        (store.default_currency.presence || store.currency.presence).to_s.upcase
      end

      def normalize_dimension(dimension)
        value = dimension.to_s.strip
        DIMENSIONS.include?(value) ? value : DEFAULT_DIMENSION
      end

      def normalize_limit(limit)
        value = begin
          Integer(limit)
        rescue ArgumentError, TypeError
          nil
        end
        return DEFAULT_LIMIT if value.nil? || value <= 0

        [value, MAX_LIMIT].min
      end

      def build_range(from, to)
        end_at = parse_time(to) || Time.current
        start_at = parse_time(from) || end_at - @window_days.days
        start_at..end_at
      end

      def parse_time(value)
        return nil if value.blank?
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return value.begin if value.is_a?(Range)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
