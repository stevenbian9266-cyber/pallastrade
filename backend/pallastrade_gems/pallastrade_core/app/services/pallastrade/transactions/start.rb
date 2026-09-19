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
      # @param option_kind [String, nil] 支付入口（method kind，如 card/apple_pay/google_pay）——
      #        D7（PRD-20260918-payments-d7-payment-section-express）：透传给
      #        `PaymentSessions::Start` 做**入口级同源校验**（不传 = 零回归）。
      # @param expected [Hash] 客户端所见 quote {checkout_version:, price_version:}
      #        （未过期场景交 P1-5 校验）
      # @return Result success({ transaction:, payment_session: }) | failure(code: ...)
      def call(order:, payment_method:, purpose: 'purchase', external_data: {}, option_kind: nil, expected: {})
        expected_version = expected[:checkout_version]
        expected_price_version = expected[:price_version]
        order = order.to_model if order.respond_to?(:to_model)
        return failure(order, 'CommerceTransaction requires a persisted order') if order.nil? || order.new_record?
        return failure(order, { code: 'invalid_transaction_purpose', message: "Unknown purpose: #{purpose}" }) unless PURPOSES.include?(purpose)

        # ① 补付重验 + quote 同意（写路径）：失效行剔除 / 优惠复核 / 抵扣再平衡 →
        #    Refresh → 商业事实变化（含前台显示金额不一致）→ quote_changed
        consent = quote_consent(order, expected: expected)
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

        # ③ 库存门（INV-P3-2，AC-3001/3002）：Reserve before PaymentSession。
        # Snapshot 已冻结 → 全部 REQUIRED inventory 成功 RESERVED → 才允许支付；
        # 失败返回 INSUFFICIENT_STOCK / INVENTORY_CHANGED，不创建 PaymentSession / PSP side effect。
        inventory_gate = PallasTrade::Transactions::ReserveInventory.call(transaction: tx)
        return inventory_gate unless inventory_gate.success?

        # ④ 支付执行（P0 结构：provider I/O 在锁外；交易锁已释放）
        # 透明 Refresh 后以最新 quote 为准，不把客户端 stale expected 带入会话。
        session_result = PallasTrade::PaymentSessions::Start.call(
          order: order,
          payment_method: payment_method,
          external_data: external_data,
          # D7（PRD-20260918-payments-d7-payment-section-express）：入口（method kind）
          # 一路透传到会话门禁——前台选的是哪个入口，服务端就按哪个入口复算可用性。
          option_kind: option_kind,
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

      # ① 补付重验（PRD-20260919-checkout）：标准流未完成订单一律先走
      # `OrderCheckout::Revalidate` 写路径——失效行剔除（+行级释放预留）/ 过期重定价 /
      # 优惠复核 / 抵扣再平衡 / Refresh 续窗；随后：
      #   - 硬阻断（就绪缺失 / 配送不可达 / 无可付商品等）→ 直接拒绝（不建会话）；
      #   - 前台显示金额（expected[:amount_due]）与服务端复算不一致 → quote_changed（带 changes[]）。
      # legacy / completed 订单直通（行为不变）。
      def quote_consent(order, expected: {})
        return success([order, false]) unless quote_gate_active?(order)

        revalidation = PallasTrade::OrderCheckout::Revalidate.call(order: order, dry_run: false)
        unless revalidation.success?
          return failure(order, revalidation.error.to_s.presence || 'Order revalidation failed')
        end

        report = revalidation.value
        order = order.reload

        blocker = Array(report['blockers']).first
        return failure(order, blocker_error(blocker)) if blocker.present?

        expected_amount = expected[:amount_due] || expected['amount_due']
        if expected_amount.present?
          # 前台路径：页面展示了金额（含重验后的新金额）→ 只比对「显示值 vs 服务端复算」
          if expected_amount.to_s != order.amount_due.to_s
            return failure(order, quote_changed_error(order, report))
          end
        elsif report['amount_due_before'].to_s != report['amount_due_after'].to_s
          # 未声明显示金额（API/legacy 客户端）：重验改变了应付金额 → 必须显式确认
          return failure(order, quote_changed_error(order, report))
        end

        # 未过期场景：客户端期望版本比对交给 PaymentSessions::Start（P1-5 checkout_version_conflict）
        success([order, !!report.dig('window', 'reissued')])
      end

      # 重验硬阻断 → 服务失败（携带结构化原因，前端展示定向动作）
      def blocker_error(blocker)
        {
          code: blocker['code'] || blocker[:code],
          message: blocker['message'] || blocker[:message]
        }.merge(blocker.except('code', 'message').transform_keys(&:to_sym))
      end

      def resume_consent_error(transaction, order)
        frozen = { price_version: transaction.price_version, amount_due: transaction.amount.to_s }
        return nil if same_money_facts?(frozen, money_facts(order))

        quote_changed_error(order)
      end

      # Payment Start Policy：交易处于 payment_confirmed/finalizing/recovery_required/
      # manual_review/completed 时禁止静默启动新支付（资金事实不可逆，INV-02/04）。
      # INV-P3-6 (FR-049)：recovery_required/manual_review 对前端暴露
      # INVENTORY_RECOVERY_REQUIRED（PAID 交易需恢复，非可重试支付错误）。
      def terminal_transaction_for(order, purpose)
        blocker = PallasTrade::CommerceTransaction.
                  joins(:transaction_orders).
                  where(transaction_orders: { order_id: order.id }).
                  where(purpose: purpose).
                  where(state: %w[payment_confirmed finalizing recovery_required manual_review completed]).
                  order(id: :desc).first
        return nil if blocker.nil?

        code = if %w[recovery_required manual_review].include?(blocker.state)
                 'INVENTORY_RECOVERY_REQUIRED'
               else
                 'transaction_not_payable'
               end
        message = if code == 'INVENTORY_RECOVERY_REQUIRED'
                    'Transaction requires recovery; use recovery instead of starting a new payment'
                  else
                    'Transaction is not payable in its current state'
                  end

        failure(order, {
                  code: code,
                  message: message,
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
        # INV-P3-2: Snapshot V2 —— 含 inventory demand evidence（FR-013/014）。
        # demand = immutable 需求证据；实时可用性仍以 Inventory Domain 为准（FR-015/INV-I12）。
        transaction.snapshot!(
          checkout_version: order.checkout_version,
          price_version: order.price_version,
          fingerprint: snapshot&.fingerprint,
          schema_version: PallasTrade::CommerceTransaction::CURRENT_SNAPSHOT_SCHEMA_VERSION,
          data: {
            schema_version: PallasTrade::CommerceTransaction::CURRENT_SNAPSHOT_SCHEMA_VERSION,
            order_id: order.prefixed_id,
            number: order.number,
            state: order.state,
            amount_due: order.amount_due.to_s,
            participant_orders: [{
              order_id: order.prefixed_id,
              allocated_amount: order.amount_due.to_s,
              inventory_demand: inventory_demand_for(order)
            }]
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

      # INV-P3-2: 参与者的 inventory demand evidence（REQUIRED/NOT_REQUIRED × quantity）。
      def inventory_demand_for(order)
        order.line_items.filter_map do |li|
          required = PallasTrade::Stock::InventoryRequirement.required?(li)
          {
            line_item_id: li.prefixed_id,
            variant_id: li.variant&.prefixed_id,
            quantity: li.quantity,
            stock_requirement: required ? 'REQUIRED' : 'NOT_REQUIRED'
          }
        end
      end

      def attach_session(session, transaction)
        return if session.nil? || !session.persisted?
        return if session.transaction_id.present? && session.transaction_id == transaction.id

        session.update!(transaction_id: transaction.id)
      end

      def quote_gate_active?(order)
        # PRD-20260919-checkout：不再要求 checkout_expires_at.present? ——
        # 无窗口的历史待支付单（如新流程之前创建）同样必须重验；
        # 窗口语义由 Revalidate 内部判定（窗口内锁价 / 无窗或过期 → 重定价 + 续窗）。
        order.standard_flow? && !order.completed?
      end

      def money_facts(order)
        { price_version: order.price_version, amount_due: order.amount_due.to_s }
      end

      # 商业事实一致：以权威应付金额（amount_due = total − payment_total）为准；
      # price_version 仅信息性（其本身就是金额指纹，见 Recalculate）。
      def same_money_facts?(facts_a, facts_b)
        facts_a[:amount_due] == facts_b[:amount_due]
      end

      def quote_changed_error(order, report = nil)
        {
          code: 'quote_changed',
          message: 'Checkout quote changed; please confirm the updated summary',
          order_id: order.prefixed_id,
          latest: {
            version: order.checkout_version,
            price_version: order.price_version,
            expires_at: order.checkout_expires_at&.iso8601,
            amount_due: order.amount_due.to_s,
            display_amount_due: order.display_amount_due.to_s,
            changes: report ? Array(report['changes']) : [],
            invalid_items: report ? Array(report['invalid_items']) : []
          }
        }
      end
    end
  end
end
