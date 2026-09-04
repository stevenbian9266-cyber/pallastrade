# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-2 (PRD-20260904-api-txn-p2-2)
#
# Transactions::Start —— durable CommerceTransaction 启动编排（单订单）。
# 职责：quote 同意（过期自动 Refresh，商业事实变化 → quote_changed）→ 幂等查找/
# 创建 active Transaction → 冻结 snapshot + 参与者 → 委托 PaymentSessions::Start
# （复用其 gate/reuse/operation_key/二次锁）→ 绑定 session.transaction_id。
#
# 设计要点（TXN-P2-0 §5/§6.5/§6.6）：
# - 商业事实 = order.price_version（Recalculate 的金额指纹）+ amount_due；与
#   checkout_version（内容版本）分离，避免 contact 等变更误触发 quote_changed。
# - Transaction Gate（本服务） + Payment defensive gate（PaymentSessions::Start）
#   双层防御；不重写 Start。
# - identity 不含版本：active transaction 复用键 = order + purpose + active 状态。
module PallasTrade
  module Transactions
    class Start
      prepend PallasTrade::ServiceModule::Base

      PURPOSES = PallasTrade::CommerceTransaction::PURPOSES

      # @param order [PallasTrade::Order]
      # @param payment_method [PallasTrade::PaymentMethod]
      # @param purpose [String] purchase | balance_collection（combined 延后，TXN-P2-5）
      # @param external_data [Hash] 透传 PaymentSessions::Start
      # @param expected [Hash] 客户端所见 quote {checkout_version:, price_version:}
      #        （未过期场景交 P1-5 校验）
      # @return Result success({ transaction:, payment_session: }) | failure(code: ...)
      def call(order:, payment_method:, purpose: 'purchase', external_data: {}, expected: {})
        expected_version = expected[:checkout_version]
        expected_price_version = expected[:price_version]
        order = order.to_model if order.respond_to?(:to_model)
        return failure(order, 'CommerceTransaction requires a persisted order') if order.nil? || order.new_record?
        return failure(order, { code: 'invalid_transaction_purpose', message: "Unknown purpose: #{purpose}" }) unless PURPOSES.include?(purpose)

        # ① quote 同意（无交易副作用）：过期 Refresh → 商业事实变化 → quote_changed
        consent = quote_consent(order)
        return consent unless consent.success?

        order, refreshed = consent.value

        # ② 交易上下文：订单锁内幂等查找/创建 + snapshot 冻结 + 参与者
        tx = order.with_lock do
          order.reload
          existing = PallasTrade::CommerceTransaction.active_for_order(order, purpose: purpose)
          if existing
            consent_error = resume_consent_error(existing, order)
            return consent_error if consent_error

            existing
          else
            blocker = terminal_transaction_for(order, purpose)
            return blocker if blocker.is_a?(PallasTrade::ServiceModule::Result)

            create_transaction!(order, purpose)
          end
        end

        # ③ 支付执行（P0 结构：provider I/O 在锁外；交易锁已释放）
        # 透明 Refresh 后以最新 quote 为准，不把客户端 stale expected 带入会话。
        session_result = PallasTrade::PaymentSessions::Start.call(
          order: order,
          payment_method: payment_method,
          external_data: external_data,
          expected_version: refreshed ? nil : expected_version,
          expected_price_version: refreshed ? nil : expected_price_version
        )
        return session_result unless session_result.success?

        session = session_result.value
        attach_session(session, tx)
        tx.start_payment! if tx.state == 'created'

        success(transaction: tx.reload, payment_session: session)
      end

      private

      # 引用 P1 行为：仅 quote-active 标准流订单走 gate；无 quote/legacy/completed
      # 账户补付 → 直通（行为与 P1-3 一致）。
      def quote_consent(order)
        return success([order, false]) unless quote_gate_active?(order)

        pre = PallasTrade::OrderCheckout::Expiration.new.expired?(order: order) ? money_facts(order) : nil
        if pre
          refresh_result = PallasTrade::OrderCheckout::Refresh.call(order: order)
          return refresh_result unless refresh_result.success?

          order = order.reload
        end

        readiness = PallasTrade::OrderCheckout::Readiness.call(order: order)
        blocking = readiness.missing_requirements & %w[contact shipping_address delivery_rate]
        if blocking.any?
          return failure(order, {
                           code: 'checkout_not_ready',
                           message: "Checkout is not ready: missing #{blocking.join(', ')}",
                           missing_requirements: blocking
                         })
        end

        return failure(order, quote_changed_error(order)) if pre && !same_money_facts?(pre, money_facts(order))

        # 未过期场景：客户端期望比对交给 PaymentSessions::Start（P1-5 checkout_version_conflict）
        success([order, pre.present?])
      end

      def resume_consent_error(transaction, order)
        frozen = { price_version: transaction.price_version, amount_due: transaction.amount.to_s }
        return nil if same_money_facts?(frozen, money_facts(order))

        quote_changed_error(order)
      end

      # Payment Start Policy：交易处于 payment_confirmed/finalizing/recovery_required/
      # manual_review/completed 时禁止静默启动新支付（资金事实不可逆，INV-02/04）。
      def terminal_transaction_for(order, purpose)
        blocker = PallasTrade::CommerceTransaction.
                  joins(:transaction_orders).
                  where(transaction_orders: { order_id: order.id }).
                  where(purpose: purpose).
                  where(state: %w[payment_confirmed finalizing recovery_required manual_review completed]).
                  order(id: :desc).first
        return nil if blocker.nil?

        failure(order, {
                  code: 'transaction_not_payable',
                  message: 'Transaction is not payable in its current state; use recovery instead',
                  transaction_id: blocker.prefixed_id,
                  state: blocker.state
                })
      end

      def create_transaction!(order, purpose)
        transaction = PallasTrade::CommerceTransaction.create!(
          store: order.store,
          customer: order.user,
          purpose: purpose,
          currency: order.currency,
          amount: order.amount_due
        )
        snapshot = PallasTrade::OrderCheckout::Snapshot.call(order: order)
        transaction.snapshot!(
          checkout_version: order.checkout_version,
          price_version: order.price_version,
          fingerprint: snapshot&.fingerprint,
          data: {
            order_id: order.prefixed_id,
            number: order.number,
            state: order.state,
            amount_due: order.amount_due.to_s,
            participant_orders: [{ order_id: order.prefixed_id, allocated_amount: order.amount_due.to_s }]
          }
        )
        PallasTrade::TransactionOrder.create!(
          commerce_transaction: transaction,
          order: order,
          role: 'primary',
          amount_snapshot: order.amount_due
        )
        transaction
      end

      def attach_session(session, transaction)
        return if session.nil? || !session.persisted?
        return if session.transaction_id.present? && session.transaction_id == transaction.id

        session.update!(transaction_id: transaction.id)
      end

      def quote_gate_active?(order)
        order.standard_flow? && !order.completed? && order.checkout_expires_at.present?
      end

      def money_facts(order)
        { price_version: order.price_version, amount_due: order.amount_due.to_s }
      end

      # 商业事实一致：以权威应付金额（amount_due = total − payment_total）为准；
      # price_version 仅信息性（其本身就是金额指纹，见 Recalculate）。
      def same_money_facts?(facts_a, facts_b)
        facts_a[:amount_due] == facts_b[:amount_due]
      end

      def quote_changed_error(order)
        {
          code: 'quote_changed',
          message: 'Checkout quote changed; please confirm the updated summary',
          order_id: order.prefixed_id,
          latest: {
            version: order.checkout_version,
            price_version: order.price_version,
            expires_at: order.checkout_expires_at&.iso8601,
            amount_due: order.amount_due.to_s,
            display_amount_due: order.display_amount_due.to_s
          }
        }
      end
    end
  end
end
