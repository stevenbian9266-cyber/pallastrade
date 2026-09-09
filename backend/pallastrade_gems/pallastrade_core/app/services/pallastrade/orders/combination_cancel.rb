module PallasTrade
  module Orders
    # Combination-level cancellation orchestration (REV-P6-8f;
    # PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration).
    #
    # Cancels a succeeded PaymentCombination's payable member orders together —
    # or only the requested subset. Each member goes through the single-order
    # Cancellation Orchestrator (Orders::Cancel), which is split-aware since
    # REV-P6-8f: a paid combo member has no local PSP payment row, so its
    # durable refund is created against the combination Payment with the frozen
    # PaymentSplit (+ target_order) ownership, then enqueued after commit
    # (AP-010 — no in-transaction sync Execute anywhere).
    #
    # Semantics:
    #   - combination must be +succeeded+; pre-payment cancellation stays on
    #     PaymentCombination#cancel (this service never touches combo/txn state);
    #   - already-canceled / not-cancellable members are skipped with a reason;
    #   - a failing member is rescued and reported — it never aborts siblings
    #     (per-member isolation, mirrors ReverseCommerce::Recover);
    #   - idempotent: re-running only acts on members still cancellable, so it
    #     never creates duplicate durable refunds.
    class CombinationCancel
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_REASON = Orders::Cancel::DEFAULT_REASON

      # @param combination [PallasTrade::PaymentCombination]
      # @param canceler [Object, nil] the user/admin who initiated the cancellation
      # @param member_ids [Array<Integer>, nil] raw order ids to target; nil = all members
      # @param reason [String] one of PallasTrade::OrderCancellation::REASONS
      # @param note [String, nil] staff-facing note
      # @param restock_items [Boolean] whether to return inventory (recorded per order)
      # @param refund_payments [Boolean, nil] forwarded three-state decision to Orders::Cancel
      # @param notify_customer [Boolean] hint for subscribers
      # @return [PallasTrade::ServiceModule::Result]
      #   success(hash): { combination_id:, members: { total, canceled, skipped, failed },
      #     canceled: [{ order_id, order_prefixed_id, order_number }],
      #     skipped: [{ order_id, order_prefixed_id, reason }],
      #     failed: [{ order_id, order_prefixed_id, error }] }
      #   failure(combination) when combination is not succeeded or no eligible members
      # rubocop:disable Metrics/ParameterLists -- 编排器签名镜像 Orders::Cancel 决策参数
      def call(combination:, canceler: nil, member_ids: nil,
               reason: DEFAULT_REASON, note: nil,
               restock_items: false, refund_payments: nil, notify_customer: false)
        # rubocop:enable Metrics/ParameterLists
        unless combination.respond_to?(:status) && combination.status == 'succeeded'
          combination.errors.add(:base, 'combination cancellation requires a succeeded payment combination')
          return failure(combination)
        end

        members = eligible_members(combination, member_ids)
        if members.empty?
          combination.errors.add(:base, 'no cancellable members in the given selection')
          return failure(combination)
        end

        canceled = []
        skipped = []
        failed = []

        members.each do |order|
          # 幂等/守卫在编排层显式裁决：已取消或不可取消 → skip（不 invoke Orders::Cancel，
          # 避免把「不可取消」误报为 failure 扰动聚合）。
          if order.canceled? || !order.allow_cancel?
            skipped << member_entry(order).merge(reason: order.canceled? ? 'already_canceled' : 'not_cancellable')
            next
          end

          begin
            result = Orders::Cancel.call(
              order: order,
              canceler: canceler,
              reason: reason,
              note: note,
              restock_items: restock_items,
              refund_payments: refund_payments,
              notify_customer: notify_customer
            )
            if result.success?
              canceled << member_entry(order)
            else
              failed << member_entry(order).merge(error: cancel_error(order, result))
            end
          rescue StandardError => e
            # 单成员异常不中断整组合（编排隔离；资金建单失败已被 Orders::Cancel 内 rescue）。
            failed << member_entry(order).merge(error: "#{e.class}: #{e.message}")
          end
        end

        # REV-P6-8k：编排实际取消 ≥1 成员 → 发组合级聚合事件（succeeded 组合仍 succeeded；区别于
        # 状态机 pre-payment cancel 的 payment_combination.canceled——语义不同不合并）。canceled==0
        # （全 skip/失败）不发，避免噪音；幂等重跑仅影响仍可取消成员，每次实际取消发一次。
        if canceled.any?
          combination.publish_event(
            'payment_combination.cancel_orchestrated',
            {
              id: combination.prefixed_id,
              status: combination.status,
              members: { total: members.size, canceled: canceled.size, skipped: skipped.size, failed: failed.size },
              canceled_order_ids: canceled.map { |m| m[:order_prefixed_id] },
              skipped_order_ids: skipped.map { |m| m[:order_prefixed_id] },
              failed_order_ids: failed.map { |m| m[:order_prefixed_id] },
              canceled_by: canceler_label(canceler)
            }
          )
        end

        success(
          combination_id: combination.id,
          members: { total: members.size, canceled: canceled.size, skipped: skipped.size, failed: failed.size },
          canceled: canceled,
          skipped: skipped,
          failed: failed
        )
      end

      private

      def canceler_label(canceler)
        case canceler
        when nil then 'system'
        when Hash then (canceler[:label] || canceler['label'] || canceler[:email] || canceler['email'] || 'system').to_s
        else canceler.respond_to?(:email) ? canceler.email.to_s.presence || 'system' : canceler.to_s.presence || 'system'
        end
      end

      def eligible_members(combination, member_ids)
        members = combination.orders.to_a
        return members if member_ids.blank?

        ids = Array(member_ids).map(&:to_i)
        members.select { |order| ids.include?(order.id) }
      end

      def member_entry(order)
        {
          order_id: order.id,
          order_prefixed_id: order.prefixed_id,
          order_number: order.number
        }
      end

      def cancel_error(order, result)
        order.errors.full_messages.to_sentence.presence ||
          (result.respond_to?(:error) ? result.error : nil) ||
          'cancellation failed'
      end
    end
  end
end
