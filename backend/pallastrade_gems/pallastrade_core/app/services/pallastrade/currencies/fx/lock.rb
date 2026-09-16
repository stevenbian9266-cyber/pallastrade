# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::Lock` —— **下单锁汇**：把「当时展示的汇率 + 加点后实际汇率」落成逐单凭证。
#
# 语义（只记录，不改价、不动钱）：
#   * 币对：`base = store.default_currency`（结算侧）、`quote = order.currency`（展示侧）；
#   * 同币种 → `signals: ['same_currency']`，**不写行**（无需锁汇）；
#   * 汇率不可用 → `signals: ['no_rate']`，**不写行**（不猜；补录汇率后可重锁）；
#   * 幂等：唯一键 `(order_id, base_currency, quote_currency)`，重复投递只更新原行（`occurrences` 递增）；
#   * 策略关闭（`fx_policy.enabled = false`）→ `signals: ['disabled']`，不写行。
#
# 铁律：只写快照表 + 审计；绝不改订单/支付金额或状态、不写资金流水、不外呼。
module PallasTrade
  module Currencies
    module Fx
      class Lock
        prepend PallasTrade::ServiceModule::Base

        # @param order [PallasTrade::Order]
        # @param at [Time] 锁汇时刻（生效窗口判定 + `locked_at`）
        # @param quote_currency [String, nil] 覆盖展示币种（默认取订单币种）
        # @param locked_on [String] 触发来源（order.submitted / manual）
        # @return [PallasTrade::ServiceModule::Result] success({ snapshot:, created:, signals: })
        def call(order:, at: Time.current, quote_currency: nil, locked_on: 'order.submitted')
          return failure(nil, 'Order is required') if order.nil?

          store = order.respond_to?(:store) ? order.store : nil
          policy = PallasTrade::Currencies::Fx::Policy.for_store(store)
          return success({ snapshot: nil, created: false, signals: ['disabled'] }) unless policy[:enabled]

          base = settlement_currency_for(store)
          quote = (quote_currency.presence || order.currency).to_s.upcase
          return success({ snapshot: nil, created: false, signals: ['no_rate'] }) if base.blank?
          return success({ snapshot: nil, created: false, signals: ['same_currency'] }) if base == quote

          resolution = PallasTrade::Currencies::Rates::Resolver.call(
            store: store, base: base, quote: quote, at: at
          )
          rate = resolution.value[:rate]
          return success({ snapshot: nil, created: false, signals: ['no_rate'] }) if rate.nil?

          snapshot = upsert_snapshot(order, store, rate, policy, at, locked_on)
          success({ snapshot: snapshot, created: @created, signals: [] })
        rescue ActiveRecord::RecordInvalid => e
          failure(nil, e.record.errors.full_messages.join(', '))
        end

        private

        def settlement_currency_for(store)
          return nil if store.nil?

          (store.default_currency.presence || store.currency.presence).to_s.upcase.presence
        end

        def upsert_snapshot(order, store, rate, policy, at, locked_on)
          snapshot = PallasTrade::FxSnapshot.find_or_initialize_by(
            order_id: order.id, base_currency: rate.base_currency, quote_currency: rate.quote_currency
          )
          @created = snapshot.new_record?
          before = @created ? nil : snapshot_snapshot(snapshot)

          snapshot.assign_attributes(
            store_id: store&.id,
            payment_id: snapshot.payment_id,
            currency_rate_id: rate.id,
            display_rate: rate.rate.to_d,
            up_charge_percent: policy[:up_charge_percent],
            effective_rate: rate.effective_rate_for(policy[:up_charge_percent]),
            rate_source: rate.source,
            locked_at: at,
            locked_on: locked_on,
            occurrences: snapshot.occurrences.to_i + 1,
            metadata: (snapshot.metadata || {}).merge(
              'order_number' => order.respond_to?(:number) ? order.number : nil,
              'rate_priority' => rate.priority,
              'rate_store_scope' => rate.store_id.nil? ? 'global' : 'store'
            )
          )
          snapshot.save!

          record_audit(snapshot, before: before) if @created
          snapshot
        end

        def snapshot_snapshot(snapshot)
          {
            display_rate: snapshot.display_rate.to_s,
            effective_rate: snapshot.effective_rate.to_s,
            up_charge_percent: snapshot.up_charge_percent.to_s,
            rate_source: snapshot.rate_source,
            locked_at: snapshot.locked_at&.iso8601
          }
        end

        def record_audit(snapshot, before:)
          PallasTrade::Audit.record(
            action: 'fx_snapshot_locked',
            actor: 'system',
            resource: snapshot,
            before: before,
            after: snapshot_snapshot(snapshot)
          )
        end
      end
    end
  end
end
