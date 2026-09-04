# frozen_string_literal: true

# PALLAS-CUSTOM: Centralize replay-safe Order payment-session startup (PRD-20260830 checkout v0.2).
module PallasTrade
  module PaymentSessions
    class Start
      prepend PallasTrade::ServiceModule::Base

      # P0-3 (PRD FR-030): active 会话复用只限「新鲜」窗口内——burst 去重
      # （双击 / provider timeout 后客户端重试）都在同分钟内发生；超过窗口的
      # pending 会话大概率已在 provider 侧过期/失效（如 Stripe cs_ 24h TTL），
      # 复用会拿到 stale client_secret 永远失败。超窗则不复用、创建新会话。
      REUSE_WINDOW = 30.minutes

      # CHK-P1-5: expected_* 可选——客户端所见 quote 期望值；不匹配 → checkout_version_conflict。
      def call(order:, payment_method:, external_data: {}, expected_version: nil, expected_price_version: nil)
        data = external_data.to_h.stringify_keys
        mode = data['mode'].presence

        # CHK-P1-3: quote 作用域 Payment Start Gate —— 在首个 Order 锁外执行
        # （Refresh 自带 with_lock；避免嵌套）。gate 未激活（无 quote/legacy/
        # completed 账户补付）→ 直通，行为与 P1-2 前完全一致。
        quote_result = ensure_fresh_quote(
          order,
          expected_version: expected_version,
          expected_price_version: expected_price_version
        )
        return quote_result unless quote_result.success?

        order, quote_refreshed = quote_result.value

        prepared = order.with_lock do
          order.reload
          amount = order.amount_due
          return failure(order, 'Order has no outstanding balance') unless amount.to_d.positive?
          return failure(order, 'Payment method is not available for this order') unless payment_method_available?(order, payment_method)

          active_session = reusable_session(order, payment_method, amount, mode)
          return success(active_session) if active_session.present?

          [amount, operation_key(order, payment_method, mode, amount), order.price_version]
        end

        amount, operation_key, price_version = prepared

        # Never keep a database transaction open while waiting on a provider.
        # Stripe receives the stable operation key, so a lost response is safe
        # to retry. Other gateways are reconciled under the second Order lock.
        session_data = data.merge('idempotency_key' => operation_key)
        session_data['price_version'] = price_version if price_version.present?
        session_data['quote_refreshed'] = true if quote_refreshed
        session = payment_method.create_payment_session(
          order: order,
          amount: amount,
          external_data: session_data
        )

        order.with_lock do
          order.reload
          winner = reusable_session(order, payment_method, amount, mode)
          if winner.present? && winner != session
            session.cancel if session.persisted? && session.can_cancel?
            return success(winner)
          end

          return success(session) if session.persisted?

          failure(session, session.errors.full_messages.to_sentence.presence || 'Could not start payment session')
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record, e.record.errors.full_messages.to_sentence)
      rescue ActiveRecord::RecordNotUnique
        order.with_lock do
          order.reload
          session = reusable_session(order, payment_method, order.amount_due, mode)
          return success(session) if session.present?
        end

        raise
      end

      private

      # CHK-P1-3: quote 作用域 Payment Start Gate。
      # gate 仅作用于「标准流、未完成、且已签发 quote（checkout_expires_at present）」
      # 的订单；无 quote 订单 / legacy cart / completed 账户补付 → 直通（行为不变）。
      #
      # 过期 → 自动 OrderCheckout::Refresh（重算+续期）后继续（金额以新权威为准，
      # 客户端经 quote_refreshed/amount 感知）；就绪缺失 → checkout_not_ready 拒绝建会话。
      # CHK-P1-5: Refresh 后比对 expected_version/expected_price_version → 不匹配
      # 返回 checkout_version_conflict（含 compact 最新 quote），不建会话。
      def ensure_fresh_quote(order, expected_version: nil, expected_price_version: nil)
        return success([order, false]) unless gate_active?(order)

        refreshed = false
        if PallasTrade::OrderCheckout::Expiration.new.expired?(order: order)
          result = PallasTrade::OrderCheckout::Refresh.call(order: order)
          return result unless result.success?

          order = result.value.order
          refreshed = true
        end

        readiness = PallasTrade::OrderCheckout::Readiness.call(order: order)
        blocking = readiness.missing_requirements & %w[contact shipping_address delivery_rate]
        if blocking.any?
          error = {
            code: 'checkout_not_ready',
            message: "Checkout is not ready: missing #{blocking.join(', ')}",
            missing_requirements: blocking
          }
          return failure(order, error)
        end

        if quote_conflict?(order, expected_version, expected_price_version)
          error = {
            code: 'checkout_version_conflict',
            message: 'Checkout quote changed; please confirm the updated summary',
            order_id: order.prefixed_id,
            latest: latest_quote(order)
          }
          return failure(order, error)
        end

        success([order, refreshed])
      end

      def gate_active?(order)
        order.standard_flow? && !order.completed? && order.checkout_expires_at.present?
      end

      # CHK-P1-5: 期望 quote 比对（两键均提供时任一不匹配即冲突）。
      def quote_conflict?(order, expected_version, expected_price_version)
        return false if expected_version.nil? && expected_price_version.nil?

        version_mismatch = expected_version.present? &&
          order.checkout_version != expected_version.to_i
        price_mismatch = expected_price_version.present? &&
          order.price_version != expected_price_version

        version_mismatch || price_mismatch
      end

      def latest_quote(order)
        {
          version: order.checkout_version,
          price_version: order.price_version,
          expires_at: order.checkout_expires_at&.iso8601,
          amount_due: order.amount_due.to_s,
          display_amount_due: order.display_amount_due.to_s
        }
      end

      def reusable_session(order, payment_method, amount, mode)
        order.payment_sessions.active.where(payment_method: payment_method).order(:id).find do |session|
          session.amount == amount &&
            session.external_data.to_h['mode'].presence == mode &&
            session.created_at >= REUSE_WINDOW.ago
        end
      end

      # Do not use Order#payment_methods here: it is memoized for rendering and
      # can be stale when a gateway is enabled immediately before checkout.
      def payment_method_available?(order, payment_method)
        order.store.payment_methods.active.available_on_front_end.
          where(id: payment_method.id).
          any? { |method| method.available_for_order?(order) }
      end

      # P0-3 (PRD FR-030/FR-031): operation_key = 稳定业务意图标识（禁随机）：
      #   order reference + payment method + mode + 权威 amount + attempt
      # - amount：金额/quote 变化 → 新 key → 不错误复用旧支付意图；
      # - attempt 计「全部已持久化会话 + 1」（不只 terminal）：每次真正创建
      #   provider session 都得到全新 key（amount 变化 / 跳过 stale 复用时不与
      #   既有 pending 会话的 key 冲突）；provider timeout 后重试（本地无新增
      #   持久化记录）仍得到相同 key → provider idempotency 返回同一 session。
      def operation_key(order, payment_method, mode, amount)
        prior_sessions = order.payment_sessions.where(payment_method: payment_method).count
        normalized_mode = mode.presence || 'default'
        amount_tag = amount.to_d.round(2).to_s('F')
        "pallastrade-order-#{order.id}-method-#{payment_method.id}-#{normalized_mode}-amount-#{amount_tag}-attempt-#{prior_sessions + 1}"
      end
    end
  end
end
