# frozen_string_literal: true

# PALLAS-CUSTOM: 合并支付载体服务（PRD-20260827 P4）——能力层服务，默认不接入任何流程（P5 收银台接线）
module PallasTrade
  module Payments
    module PaymentCombinations
      # 发起一次合并支付：把多笔未支付订单打包成一个 PaymentCombination。
      #
      # 设计约束（与 payments SKILL 一致，吸取 PaymentGroup 失败教训）：
      #   - 一个组合 → 一个 PaymentSession（挂 primary order）+ 一个 Payment（挂组合，order_id=nil）
      #   - 每成员订单一条 PaymentSplit（payment 在支付前为空，Complete 时回填）
      #   - 金额服务端计算：amount = Σ 未支付订单 amount_due（防客户端篡改）
      #
      # @param store [PallasTrade::Store]
      # @param customer [User, nil]
      # @param orders [Array<PallasTrade::Order>] 待合并支付订单（未支付订单才计入金额）
      # @param payment_method [PallasTrade::PaymentMethod] 收银台支付方式
      # @param primary_order [PallasTrade::Order, nil] 挂 PaymentSession 的订单（默认第一笔）
      # @return [PallasTrade::ServiceModule::Result] success(combination) / failure(orders, message)
      class Create
        prepend PallasTrade::ServiceModule::Base

        def call(store:, customer:, orders:, payment_method:, primary_order: nil)
          orders = Array(orders).map(&:to_model)
          return failure(nil, 'Combination requires at least one order') if orders.empty?

          primary_order ||= orders.first
          return failure(orders, 'Primary order must be a member order') unless orders.include?(primary_order)

          return failure(orders, 'Orders must belong to the same store') if orders.map(&:store_id).uniq.many?
          return failure(orders, 'Orders must belong to the same customer') if customer.present? && orders.any? { |o| o.user_id != customer.id }

          currencies = orders.map(&:currency).uniq
          return failure(orders, 'Orders must share the same currency') if currencies.many?

          unpaid = orders.select { |o| o.outstanding_balance.to_f.positive? }
          return failure(orders, 'No unpaid orders to combine') if unpaid.empty?

          # 金额服务端计算：Σ 未支付订单 amount_due
          amount = unpaid.sum { |o| o.amount_due.to_f }

          combination = nil
          PallasTrade::PaymentCombination.transaction do
            # review 批2 (bugfix A1): active 守卫 —— 锁成员订单（按 id 排序防死锁）串行化
            # 同订单集并发创建；任一未支付成员已属 active（pending/processing）组合或有
            # active 交易（created/payment_pending）→ 拒绝。对齐 Transactions::Start 的
            # active_for_order 复用语义，防并发双击/超时重试建双组合双 session 双扣。
            lock_member_orders(unpaid)
            guard = active_guard_for(unpaid)
            return guard unless guard.nil?

            combination = PallasTrade::PaymentCombination.create!(
              store: store, customer: customer, currency: currencies.first, amount: amount
            )
            combination.process! # pending → processing

            unpaid.each do |order|
              PallasTrade::PaymentSplit.create!(
                payment_combination: combination,
                order: order,
                currency: currencies.first,
                authorized_amount: 0,
                captured_amount: 0,
                refunded_amount: 0
              )
            end

            # 在 primary 订单上创建支付会话（金额 = 组合合计），随后挂到组合（保持 1:1）
            session = payment_method.create_payment_session(
              order: primary_order,
              amount: amount,
              external_data: { payment_combination_id: combination.prefixed_id }
            )
            session.update!(payment_combination: combination)

            # TXN-P2 (2026-09-05)：组合即建 durable CommerceTransaction（combined_payment）
            # ——每 unpaid 成员一笔 TransactionOrder（primary 首单=primary，其余 participant），
            # 绑定 session.transaction_id 与 txn.payment_combination；PSP 成功后的入账/成员
            # 完成统一经 OnPaymentSuccess → Transactions::Finalize（组合分支）。
            wrap_in_transaction!(combination, primary_order, unpaid, session)

            combination.reload
          end

          success(combination)
        end

        private

        # 按 id 排序锁全部成员订单（死锁避免），串行化同订单集的并发组合创建。
        def lock_member_orders(orders)
          ids = orders.map(&:id).sort
          PallasTrade::Order.where(id: ids).lock.order(:id).load
        end

        # 任一成员已属 active 组合（pending/processing）或已有 active 交易
        # （created/payment_pending，含自己上次失败残留）→ 返回 failure；无冲突返回 nil。
        # review 批3b-1 (A3): 已带记账分摊（combination=nil accounting split，captured>0）的
        # 订单（拆单产物）再入组合 → 同 order 双 split 分叉 + OrderUpdater last-wins 虚高
        # outstanding → 可重复扣款窗口。拒绝（需先结算/合并 accounting split）。
        def active_guard_for(orders)
          accounting = PallasTrade::PaymentSplit.where(order_id: orders.map(&:id))
                                                .where(payment_combination_id: nil)
                                                .where('captured_amount > 0')
                                                .exists?
          if accounting
            return failure(orders,
                           'One or more orders have an outstanding accounting split; settle or merge it before combining')
          end

          combo_ids = PallasTrade::PaymentSplit.where(order_id: orders.map(&:id))
                                               .where.not(payment_combination_id: nil)
                                               .distinct.pluck(:payment_combination_id)
          if combo_ids.any?
            active = PallasTrade::PaymentCombination.where(id: combo_ids)
                                                    .where(status: %w[pending processing])
                                                    .first
            if active
              return failure(orders, 'One or more orders already belong to an active payment combination')
            end
          end

          has_active_txn = false
          txn_ids = PallasTrade::TransactionOrder.where(order_id: orders.map(&:id))
                                                 .pluck(:transaction_id).compact
          if txn_ids.any?
            has_active_txn = PallasTrade::CommerceTransaction.where(id: txn_ids)
                                                            .where(state: %w[created payment_pending])
                                                            .exists?
          end
          return failure(orders, 'One or more orders already have an active payment transaction') if has_active_txn

          nil
        end

        # durable CommerceTransaction 包装（purpose=combined_payment）。
        # 幂等安全：Create 每次新组合 → 新 txn；无 quote 快照（订单已提交、金额服务端算）。
        def wrap_in_transaction!(combination, primary_order, unpaid, session)
          transaction = PallasTrade::CommerceTransaction.create!(
            store: combination.store,
            customer: combination.customer,
            payment_combination: combination,
            currency: combination.currency,
            amount: combination.amount,
            purpose: 'combined_payment'
          )

          unpaid.each do |order|
            PallasTrade::TransactionOrder.create!(
              commerce_transaction: transaction,
              order: order,
              role: order == primary_order ? 'primary' : 'participant',
              amount_snapshot: order.amount_due,
              completion_status: 'pending'
            )
          end

          session.update!(transaction_id: transaction.id)
          transaction.start_payment! # created → payment_pending
        end
      end
    end
  end
end
