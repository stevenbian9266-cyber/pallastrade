# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 费率模型）——
# `Payments::Fees::Resolver` —— 给定「支付上下文」，找出**适用的唯一费率策略**。
#
# 优先级（与 `PaymentFeePolicy.by_priority` 同一 SQL 口径）：`method` > `provider` > `store` > `global`；
# 同优先级取 `effective_from` 更晚者，再取 id 更大者（**确定性**：同输入必得同策略）。
#
# 条件的处理原则是「**不猜**」：策略声明了卡类型/地区而上下文拿不到 → 视为不匹配并留 signal
# （报表会把这类支付计入「未定价」，绝不臆造一个费率）。
#
# 只读：不写库、不调 provider。
module PallasTrade
  module Payments
    module Fees
      class Resolver
        prepend PallasTrade::ServiceModule::Base

        # 解析上下文（只从**本地可得事实**构造；拿不到的一律留 nil，交给策略层判定）
        Context = Struct.new(
          :store_id, :store, :payment_method_id, :method_key, :currency, :card_type, :region, :order_country,
          :amount, :order_id,
          keyword_init: true
        ) do
          # @param payment [PallasTrade::Payment]
          # @param with_region [Boolean] 仅当有策略声明地区/基准国时才解析（避免无谓的地址查询 = N+1）
          # @param with_card_type [Boolean] 仅当有策略声明卡类型时才解析
          # @return [Context]
          def self.from_payment(payment, with_region: true, with_card_type: true)
            order = payment.respond_to?(:order) ? payment.order : nil
            method = payment.respond_to?(:payment_method) ? payment.payment_method : nil
            country = with_region ? country_for(order) : nil

            new(
              store_id: order&.store_id,
              # 不在这里取 `order.store`（未预加载时= 逐笔一次查询）；需要 store 对象时由调用方显式注入
              store: nil,
              payment_method_id: payment.respond_to?(:payment_method_id) ? payment.payment_method_id : nil,
              method_key: method_key_for(method),
              currency: order.respond_to?(:currency) ? order.currency : nil,
              card_type: with_card_type ? card_type_for(payment) : nil,
              region: country,
              order_country: country,
              amount: payment.respond_to?(:amount) ? payment.amount : nil,
              order_id: order&.id
            )
          end

          def self.method_key_for(payment_method)
            return nil if payment_method.nil?
            return nil unless payment_method.respond_to?(:effective_payment_option)

            option = payment_method.effective_payment_option
            option.present? ? (option['kind'] || option[:kind]).presence : nil
          rescue StandardError
            nil
          end

          # 仅当本地确实持有卡对象时才有卡类型（Bogus / 非卡源 → nil，不猜）
          def self.card_type_for(payment)
            source = payment.respond_to?(:source) ? payment.source : nil
            return nil if source.nil?
            return nil unless source.respond_to?(:cc_type)

            source.cc_type.presence
          rescue StandardError
            nil
          end

          def self.country_for(order)
            address = order.respond_to?(:bill_address) ? order.bill_address : nil
            return nil if address.nil?

            country = address.respond_to?(:country) ? address.country : nil
            country.respond_to?(:iso) ? country.iso.presence : nil
          rescue StandardError
            nil
          end
        end

        # @param context [Context, Hash]
        # @param at [Time] 参照时刻（生效窗口判定）
        # @param candidates [Array<PallasTrade::PaymentFeePolicy>, nil] 预加载候选（报表批量场景，避免 N+1）
        # @return [PallasTrade::ServiceModule::Result] success({policy:, signals:, skipped:, candidates:})
        def call(context:, at: Time.current, candidates: nil, store: nil)
          context = normalize_context(context)
          list = candidates || candidates_for(context, at, store)

          skipped = []
          matched = nil
          signals = []

          list.each do |policy|
            ok, policy_signals = policy.matches_context?(context_hash(context))
            if ok
              matched = policy
              signals = policy_signals
              break
            end

            skipped << { policy_id: policy.id, scope_type: policy.scope_type, reason: policy_signals.first } if skipped.size < 10
          end

          success({
                    policy: matched,
                    signals: signals,
                    skipped: skipped,
                    candidates: list.size,
                    context: context_hash(context)
                  })
        end

        private

        def normalize_context(context)
          return context if context.is_a?(Context)

          Context.new(**(context || {}).symbolize_keys)
        end

        def context_hash(context)
          {
            store_id: context.store_id,
            payment_method_id: context.payment_method_id,
            method_key: context.method_key,
            currency: context.currency,
            card_type: context.card_type,
            region: context.region,
            order_country: context.order_country
          }
        end

        # 候选取「全局 + 本店」的生效策略，按优先级排序（单次查询）
        def candidates_for(context, at, store)
          scope = store || context.store || store_from_id(context.store_id)
          PallasTrade::PaymentFeePolicy.for_store(scope).active.effective_at(at).by_priority.to_a
        end

        def store_from_id(store_id)
          return nil if store_id.blank?

          PallasTrade::Store.find_by(id: store_id)
        end
      end
    end
  end
end
