# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# `Risk::Rules::Condition` —— **单条规则的条件匹配**（条件词汇的唯一实现）。
#
# 语义（唯一权威）：
#   * `conditions` 是**白名单键的 AND 组合**：全部满足 = 命中（`matched: true`）；
#   * **不可判定 → 不命中**（绝不「猜」成命中）：缺失主体、跨币种比较、未知键都记入 `skipped`；
#   * 只读：零写库、零 provider I/O、不改订单（本服务只读订单与其本地关联）。
#
# 条件词汇（与 PRD FR-002 一一对应；新增键必须同时改 `Schema::SUPPORTED_KEYS` 与本文档）：
#   amount_gte / amount_lte       订单 total（仅当订单币种 == 店铺默认币种才可比，否则 skip: currency_mismatch）
#   currency_in                   订单币种（大写 ISO）
#   country_in                    账单地址国家 ISO2（缺失 → skip: country_missing）
#   email_domain_in / email_present  邮箱域名 / 邮箱是否存在（缺失 → skip: email_missing）
#   ip_present                    是否记录了 IP（**不做**地理/网段判定：无离线库，不猜）
#   card_brand_in                 已完成卡支付的品牌（归一：mastercard|maestro → master、amex → american_express）
#   customer_orders_gte           同客户**已完成**订单数（匿名单 → skip: customer_missing）
#   velocity_count_gte(+velocity_window_minutes)  同邮箱或同 IP 在窗口内的订单数（主体缺失 → skip: velocity_subject_missing）
#
# 不可得主体：BIN（`pallastrade_credit_cards` 无 BIN 列）、设备指纹（平台无采集）→ **不提供条件键**。
module PallasTrade
  module Risk
    module Rules
      class Condition
        prepend PallasTrade::ServiceModule::Base

        SUPPORTED_KEYS = %w[
          amount_gte amount_lte currency_in country_in email_domain_in email_present
          ip_present card_brand_in customer_orders_gte velocity_count_gte velocity_window_minutes
        ].freeze

        # 与 `CreditCard#cc_type` 同词汇（口径同 `Disputes::RateReport::BRAND_ALIASES`；
        # 此处独立定义以免 risk 域依赖 disputes 域）
        CARD_BRAND_ALIASES = {
          'mastercard' => 'master', 'maestro' => 'master', 'amex' => 'american_express'
        }.freeze

        CARD_SOURCE_TYPE = 'PallasTrade::CreditCard'
        DEFAULT_VELOCITY_WINDOW_MINUTES = 60
        MAX_VELOCITY_WINDOW_MINUTES = 10_080

        # @param order [PallasTrade::Order]
        # @param conditions [Hash] 已通过 `Schema` 校验的条件
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success({ matched:, skipped:, observed: })
        def call(order:, conditions:, now: Time.current)
          return success(matched: false, skipped: ['order_missing'], observed: {}) if order.nil?

          @order = order
          @now = now
          @conditions = conditions.to_h.stringify_keys
          @skipped = []

          matched = @conditions.all? { |key, value| match_condition(key.to_s, value) }

          success(matched: matched, skipped: @skipped, observed: observed_facts)
        end

        private

        def match_condition(key, value)
          case key
          when 'amount_gte' then compare_amount { |amount| amount >= value.to_d }
          when 'amount_lte' then compare_amount { |amount| amount <= value.to_d }
          when 'currency_in' then include_value?(currency_in_list(value), currency)
          when 'country_in' then presence_gated(country, 'country_missing') { |val| include_value?(value, val) }
          when 'email_domain_in' then domain_match(value)
          when 'email_present' then presence_gated(email, 'email_missing') { |val| value ? val.present? : val.blank? }
          when 'ip_present' then ip_gate(value)
          when 'card_brand_in' then include_value?(normalize_list(value), card_brand)
          when 'customer_orders_gte' then customer_orders_gate(value)
          when 'velocity_count_gte' then velocity_gate(key, value)
          when 'velocity_window_minutes' then true # 由 velocity_count_gte 消费（单独出现无判定意义）
          else
            @skipped << "unsupported_condition:#{key}"
            false
          end
        end

        # === 各条件的取值与闸门 ===

        # 金额比较：仅在「订单币种 == 店铺默认币种」时可比；否则 skip（不跨币种猜）
        def compare_amount
          default_currency = store_default_currency
          if default_currency.present? && currency.present? && currency != default_currency
            @skipped << 'currency_mismatch'
            return false
          end

          yield(@order.total.to_d)
        end

        def currency_in_list(value)
          normalize_list(value).map(&:upcase)
        end

        def domain_match(value)
          presence_gated(email, 'email_missing') do |mail|
            include_value?(normalize_list(value), mail.split('@').last.to_s.downcase)
          end
        end

        # `ip_present: true` 需有 IP；`ip_present: false` 需确实没有 IP（两者都要求订单可判）
        def ip_gate(value)
          present = ip.present?
          value ? present : !present
        end

        def customer_orders_gate(threshold)
          user = @order.respond_to?(:user) ? @order.user : nil
          if user.nil?
            @skipped << 'customer_missing'
            return false
          end

          count = user.orders.for_store(@order.store).where(state: 'complete').count
          count >= threshold.to_i
        end

        # velocity：同邮箱**或**同 IP 在窗口内的订单数（两者皆缺 → skip；**含当前订单**）
        def velocity_gate(_key, threshold)
          clauses = []
          binds = []
          if email.present?
            clauses << 'LOWER(pallastrade_orders.email) = ?'
            binds << email
          end
          if ip.present?
            clauses << 'pallastrade_orders.last_ip_address = ?'
            binds << ip
          end
          if clauses.empty?
            @skipped << 'velocity_subject_missing'
            return false
          end

          window = window_minutes_for
          scope = PallasTrade::Order.for_store(@order.store)
                                   .where(created_at: @now - window.minutes..@now)
                                   .where(clauses.join(' OR '), *binds)
          scope.count >= threshold.to_i
        end

        # 窗口分钟数来自同一条件的 `velocity_window_minutes`（未给 → 默认 60 分钟）
        def window_minutes_for
          minutes = @conditions['velocity_window_minutes'] || DEFAULT_VELOCITY_WINDOW_MINUTES
          minutes.to_i.clamp(1, MAX_VELOCITY_WINDOW_MINUTES)
        end

        # === 事实（全部本地、只读） ===

        def observed_facts
          {
            'amount' => @order.total.to_d.to_s('F'),
            'currency' => currency,
            'country' => country,
            'email_present' => email.present?,
            'ip_present' => ip.present?,
            'card_brand' => card_brand
          }
        end

        def currency
          value = @order.respond_to?(:currency) ? @order.currency : nil
          value.to_s.strip.upcase.presence
        end

        def store_default_currency
          store = @order.respond_to?(:store) ? @order.store : nil
          store&.default_currency.to_s.strip.upcase.presence
        end

        def country
          address = @order.respond_to?(:bill_address) ? @order.bill_address : nil
          address&.country&.iso.to_s.strip.upcase.presence
        rescue StandardError
          nil
        end

        def email
          value = @order.respond_to?(:email) ? @order.email : nil
          value.to_s.strip.downcase.presence
        end

        def ip
          value = @order.respond_to?(:last_ip_address) ? @order.last_ip_address : nil
          value.to_s.strip.presence
        end

        # 已完成卡支付的品牌（按 id 倒序取最近一笔，归一后返回）
        def card_brand
          payment = @order.payments.select do |row|
            row.source_type.to_s == CARD_SOURCE_TYPE && row.state.to_s == 'completed'
          end.max_by(&:id)
          return nil if payment.nil?

          brand = payment.source&.cc_type.to_s.strip.downcase.presence
          brand && CARD_BRAND_ALIASES.fetch(brand, brand)
        rescue StandardError
          nil
        end

        # === 小工具 ===

        # 主体缺失 → 记 skip 且**不命中**（不猜）
        def presence_gated(value, reason)
          if value.blank?
            @skipped << reason
            return false
          end

          yield(value)
        end

        # 列表命中（大小写不敏感：``Schema`` 已归一，这里再容错一次（运营手写小写也不会静默不命中）
        def include_value?(list, value)
          return false if value.blank?

          target = value.to_s.downcase
          Array(list).any? { |item| item.to_s.strip.downcase == target }
        end

        def normalize_list(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:blank?)
        end
      end
    end
  end
end
