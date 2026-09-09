module PallasTrade
  module Orders
    class Cancel
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_REASON = 'other'.freeze

      # Cancels an order and records a PallasTrade::OrderCancellation history record.
      # Legacy `canceler:` and `canceled_at:` remain valid; new keywords are additive.
      #
      # @param order [PallasTrade::Order]
      # @param canceler [Object, nil] the user/admin who initiated the cancellation
      # @param canceled_at [Time, nil] timestamp (defaults to Time.current)
      # @param reason [String] one of PallasTrade::OrderCancellation::REASONS
      # @param note [String, nil] staff-facing note
      # @param restock_items [Boolean] whether to return inventory
      # @param refund_payments [Boolean] whether to refund captured payments
      # @param refund_amount [BigDecimal, Numeric, nil] amount to refund;
      #   when refund_payments is true and this is nil, defaults to order.payment_total
      # @param notify_customer [Boolean] hint for subscribers
      # @return [PallasTrade::ServiceModule::Result]
      # rubocop:disable Metrics/ParameterLists -- 既有 P7 服务签名，保持调用方兼容
      def call(order:, canceler: nil, canceled_at: nil,
               reason: DEFAULT_REASON, note: nil,
               restock_items: false, refund_payments: nil, refund_amount: nil,
               notify_customer: false)
        # rubocop:enable Metrics/ParameterLists
        canceled_at ||= Time.current
        reason = DEFAULT_REASON if reason.blank? # controller 透传空值时不覆盖默认
        # DB 列 NOT NULL：调用方缺省/显式 nil 时回落 false（不改变旧行为）
        restock_items = false if restock_items.nil?
        notify_customer = false if notify_customer.nil?

        # REV-P6-4：refund_payments 三态（nil=auto / true=退 / false=显式不退）。
        # auto：取消时点存在可退 PSP completed payment → 退款（保持现网默认语义）；
        # 显式 false → 即使 PAID 也不建 Refund（AC-R64-03）。
        # REV-P6-8f（FR-R68F-101）：succeeded 组合成员的资金在组合 Payment + 冻结 split 上
        # （无本地 PSP payment 行）——auto 视该 split 为可退源，修复 REV-P6-4 后「PAID 组合成员取消零退款」。
        refundable_payments = completed_refundable_payments(order)
        member_split = combination_member_split(order, refundable_payments)
        will_refund = refund_payments == false ? false : (refund_payments == true || refundable_payments.any? || member_split.present?)

        # refund_amount 仅支持单一可退源（单笔可退 PSP 支付或单一组合 split；不可证明不猜，
        # REV-P6-3 同原则）。
        if refund_amount.present? && (refundable_payments.size + (member_split ? 1 : 0)) > 1
          order.errors.add(:base, 'refund_amount is only supported for orders with a single refundable PSP payment')
          return failure(order)
        end

        # INV-P3-4：取消决策时点的"可释放"判定（取消动作可能改变支付状态，
        # 故必须在取消前基于权威支付事实捕获，避免把 PAID 误判为未付而错误 Release）。
        release_allowed = !paid_or_in_flight?(order)

        refunds = []
        rolled_back = false
        order.transaction do
          # REV-P6-8j（§34）：OrderCancellation = durable 取消意图；新行进入 requested，取消成功后同事务
          # 转为 applied（订单 canceled + durable refunds 已建）。失败/回滚 → 整行不存（REV-P6-4 不变式）。
          cancellation = order.cancellations.create!(
            reason: reason,
            note: note,
            restock_items: restock_items,
            refund_payments: will_refund,
            refund_amount: refund_amount,
            notify_customer: notify_customer,
            canceled_by: canceler,
            created_at: canceled_at,
            state: 'requested'
          )

          changes = { canceled_at: canceled_at }
          changes[:canceler_id] = canceler.id if canceler.present?
          order.update_columns(changes)

          # REV-P6-4：PAID 退款在 order.cancel! 之前按 durable intent 显式建
          # Refund(requested)（enqueue:false——事务提交后再统一入队，避免回滚孤儿入队）。
          # 建单失败 → 回滚整个取消（不留半取消 + 无 evidence 状态）。
          built = build_refunds_if_paid(order, will_refund, refund_amount)
          unless built
            rolled_back = true
            order.errors.add(:base, 'refund could not be requested; order cancellation aborted')
            raise ActiveRecord::Rollback
          end
          refunds = built
          order.cancel!
          # REV-P6-8j：取消应用成功 → durable intent applied（与取消同事务原子）
          cancellation.apply!
        end
        if rolled_back
          return failure(order)
        end

        # INV-P3-4 (FR-033/FR-032): 取消后释放"未消费且确未支付"的 RESERVED → RELEASED。
        # PAID / 进行中 attempt（可能 webhook 迟到变 PAID）→ 不自动 Release（INV-I09）。
        release_unpaid_reservations(order) if release_allowed

        # REV-P6-4：durable requested 行已提交 → 异步执行（资金 I/O 只走 ExecuteJob）。
        refunds.each { |refund| PallasTrade::Refunds::ExecuteJob.perform_later(refund.id) }

        order.publish_event('order.canceled', order.event_payload.merge(notify_customer: notify_customer))
        success(order.reload)
      rescue ActiveRecord::RecordInvalid, StateMachines::InvalidTransition
        failure(order)
      end

      private

      # REV-P6-4：可退 PSP completed payments（排除 store credit——店内账户非 PSP 外部
      # 资金，由 after_cancel 同步 credit-back 保留；与 REV-P6-2 gateway cancel 的
      # for_shipment 例外同语义：运费单整体退款由运费退款承担）。
      # 用 fresh query（不走 order.payments association——Payment#invalidate_old_payments
      # 可能把空 target 缓存到 order 实例，导致 association.first/scope 读到陈旧空集）。
      def completed_refundable_payments(order)
        PallasTrade::Payment.where(order_id: order.id).valid.completed.not_store_credits.select do |p|
          p.credit_allowed.to_f.positive? && !(p.respond_to?(:for_shipment?) && p.for_shipment?)
        end
      end

      # REV-P6-8f：succeeded 组合成员的权威可退源 = 冻结 PaymentSplit。组合资金在组合 Payment
      # （order_id=nil）上，成员订单无本地 PSP payment 行（settlement 已把 split.payment 回填为
      # 组合 payment）——REV-P6-4 的本地查询对成员返回空正是「PAID 组合成员取消零退款」根因。
      # 仅当订单确无本地可退 PSP payment、存在 succeeded 组合 split 且 credit_allowed > 0 时启用
      # （否则维持既有本地 payment 语义，避免双源歧义）。
      def combination_member_split(order, refundable_payments = nil)
        refundable_payments ||= completed_refundable_payments(order)
        return nil if refundable_payments.any?

        PallasTrade::PaymentSplit
          .joins(:payment_combination)
          .where(order_id: order.id, pallastrade_payment_combinations: { status: 'succeeded' })
          .where.not(payment_id: nil)
          .select { |split| split.credit_allowed.to_f.positive? }
          .first
      end

      # REV-P6-4：在订单事务内为已决策退款的 completed PSP 支付建 durable
      # Refund(requested)（Refunds::Request，enqueue:false）。金额：refund_amount 存在时
      # 取 min(refund_amount, payment.credit_allowed)（调用方已保证单笔）；否则全 credit_allowed
      # （与旧隐式 after_cancel 全退语义一致）。任一建单失败 → 返回 nil（调用方回滚）。
      # REV-P6-8f：无本地 PSP payment 的 succeeded 组合成员 → 组合 Payment + 冻结 split 退款
      # （payment_split/target_order ownership 可证明才传；split 上限由
      # Refund#amount_within_frozen_split_limit 强制执行，不碰兄弟 split）。
      def build_refunds_if_paid(order, will_refund, refund_amount)
        return [] unless will_refund

        payments = completed_refundable_payments(order)
        if payments.any?
          built = []
          payments.each do |payment|
            amount = refund_amount.present? ? [refund_amount.to_d, payment.credit_allowed.to_d].min : payment.credit_allowed
            result = PallasTrade::Refunds::Request.call(
              payment: payment,
              amount: amount,
              reason: PallasTrade::RefundReason.order_canceled_reason,
              refunder_id: order.canceler_id,
              enqueue: false
            )
            return nil unless result.success?

            built << result.value
          end
          return built
        end

        split = combination_member_split(order)
        return [] unless split

        amount = refund_amount.present? ? [refund_amount.to_d, split.credit_allowed.to_d].min : split.credit_allowed
        result = PallasTrade::Refunds::Request.call(
          payment: split.payment,
          amount: amount,
          reason: PallasTrade::RefundReason.order_canceled_reason,
          refunder_id: order.canceler_id,
          payment_split: split,
          target_order: order,
          enqueue: false
        )
        return nil unless result.success?

        [result.value]
      end

      # 仅当订单确未支付（无 completed payment / payment_total=0）且无进行中支付 attempt
      # 时释放 reservation；COMMITTED 行（售后/已完成）天然不受 Release 影响（FR-034）。
      def release_unpaid_reservations(order)
        return if paid_or_in_flight?(order)

        PallasTrade::StockReservations::Release.call(order: order, reason: 'order_canceled')
      end

      def paid_or_in_flight?(order)
        return true if order.payment_total.to_f.positive?
        return true if PallasTrade::Payment.where(order_id: order.id).valid.completed.exists?

        transaction = PallasTrade::CommerceTransaction.active_for_order(order)
        transaction.present? && transaction.payment_sessions.exists?
      end
    end
  end
end
