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
      def call(order:, payment_method:, external_data: {}, expected_version: nil, expected_price_version: nil,
               option_kind: nil)
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
          # D8（PRD-20260915-payments-d8 切片1）：入口级可用性同源复算（§66.5）——被范围规则/配置
          # 排除的入口 → 结构化错误 payment_option_not_available（§76.4），且不建会话。
          unless payment_method_available?(order, payment_method, option_kind: option_kind)
            return failure(order, {
              code: 'payment_option_not_available',
              message: 'Payment method is not available for this order',
              # D15 切片3（PRD-20260917-checkout-d15-切片3）：把「为什么不可用」说清楚
              # —— `authentication_required` = 本单要求 3DS/SCA，而该入口拿不到强认证。
              reason: rejection_reason(order, payment_method, option_kind: option_kind)
            })
          end

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
        # D9（PRD-20260915-payments-d9 切片1）：test 环境凭据产生的会话打标（对账/报表可排除非真实资金）。
        session_data['test_mode'] = true if payment_method.test_environment?
        # D15 切片3：认证需求 → provider 指令（仅对**声明了能力**的入口下发；否则不下发、不猜）。
        auth = PallasTrade::Payments::ThreeDSecure::Required.for_order(order)
        hint = PallasTrade::Payments::ThreeDSecure::ProviderHint.call(
          payment_method: payment_method, option_kind: option_kind, required: auth[:required]
        ).value || {}
        session_data.merge!(hint['external_data'].to_h)
        # 留痕只在「本单被要求认证」时写（`applied` / `none`）——不要求时保持 external_data 与今天逐字节一致
        session_data['three_d_secure_hint'] = hint['hint'] if auth[:required]
        session = payment_method.create_payment_session(
          order: order,
          amount: amount,
          external_data: session_data
        )

        # D15 切片3：留痕事件（仅在「要求认证 **且** 真的建了会话」时发一次；payload 无 PII）。
        publish_authentication_event(order, auth, hint) if auth[:required] && session.persisted?

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
      # PRD-20260919-checkout：保持该契约作为**防御层**（新流程订单建单即签发窗口，
      # 因此实际都会走 gate）；补付重验（失效行剔除/优惠复核/抵扣再平衡）的**唯一权威**
      # 在 `Transactions::Start` → `OrderCheckout::Revalidate`，此处不重复执行。
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

      # D15 切片3：拒绝原因分类（可解释；不额外打 provider）
      #   authentication_required —— 本单要求认证而该入口拿不到强认证（闸门主因）
      #   scope_rule             —— 适用范围/熔断/配置导致的不可用（D8/D11 既有语义）
      def rejection_reason(order, payment_method, option_kind: nil)
        auth = PallasTrade::Payments::ThreeDSecure::Required.for_order(order)
        kind = option_kind.to_s.presence || payment_method.default_option_kind.to_s
        return 'scope_rule' unless auth[:required]

        PallasTrade::Payments::ThreeDSecure::ProviderHint.option_supported?(payment_method, kind) ? 'scope_rule' : 'authentication_required'
      end

      AUTHENTICATION_EVENT = 'payment.three_d_secure_required'

      # 认证需求事件：只描述事实（策略模式 / 来源 / 豁免 / 风险动作 / 下发结果），无 PII。
      # 事件系统未启用或发布失败**不阻断**支付路径（与 D15 切片2 同口径）。
      def publish_authentication_event(order, auth, hint)
        return unless PallasTrade::Events.respond_to?(:enabled?) && PallasTrade::Events.enabled?

        PallasTrade::Events.publish(
          AUTHENTICATION_EVENT,
          store_id: order.store_id,
          payload: {
            'order_id' => order.id,
            'mode' => auth[:mode],
            'source' => auth[:source],
            'reason' => auth[:reason],
            'exemptions' => Array(auth[:exemptions]),
            'risk_action' => auth[:risk_action],
            'provider_hint' => hint['hint']
          }
        )
      rescue StandardError
        nil
      end

      # Do not use Order#payment_methods here: it is memoized for rendering and
      # can be stale when a gateway is enabled immediately before checkout.
      def payment_method_available?(order, payment_method, option_kind: nil)
        available = order.store.payment_methods.active.available_on_front_end.
          where(id: payment_method.id).
          any? { |method| method.frontend_visible? && method.available_for_order?(order) }
        return false unless available

        option_available?(order, payment_method, option_kind)
      end

      # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915 切片2 / FR-003 / AC-002）
      #                 D8（PRD-20260915-payments-d8 切片1 / AC-004）—— 同源复算（§66.5）
      # 入口（method kind）级校验：
      # - 该 provider 无任何可用入口（含被「适用范围」规则排除）→ 拒绝；
      # - 未传 option_kind → 不校验具体入口（行为与改动前一致，零回归）；
      # - 传了 option_kind → 必须落在「配置 ∪ 范围规则」都通过的可用入口集合内；
      #   未配置 options 的 provider 只接受自己的默认入口 kind（默认回落语义，见 effective_payment_options）。
      def option_available?(order, payment_method, option_kind)
        available_options = PallasTrade::Payments::Availability::Resolver.available_options(
          order: order, payment_method: payment_method
        )
        return false if available_options.empty?

        kind = option_kind.to_s.presence
        return true if kind.blank?

        available_options.any? { |option| option['kind'] == kind }
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
