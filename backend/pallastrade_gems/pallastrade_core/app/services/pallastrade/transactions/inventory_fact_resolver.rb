# frozen_string_literal: true

module PallasTrade
  module Transactions
    # INV-P3-5 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-..., FR-041/042):
    # InventoryFactResolver —— 判定一个 CommerceTransaction 的**库存事实**（只读、零副作用，
    # 参照 PaymentFactResolver 的职责边界）。不推进状态机、不创建/修改 Reservation。
    #
    # 输出 verdict：NOT_REQUIRED / UNRESERVED / RESERVED / COMMITTED / RELEASED /
    #   EXPIRED / AMBIGUOUS（组合多 participant 不一致折叠为 AMBIGUOUS，PARTIAL 不单独暴露）。
    #
    # COMMITTED 判定不只依赖 Reservation.state：需对应订单已完成/终态（finalization 证据）
    # 且该 line_item 有 COMMITTED 覆盖；若 COMMITTED 与订单完成事实不一致 → AMBIGUOUS（FR-042）。
    class InventoryFactResolver
      prepend PallasTrade::ServiceModule::Base

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return Result success({ verdict: Symbol, reasons: [Symbol], items: [Hash] })
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        orders = transaction.transaction_orders.includes(:order).filter_map(&:order).uniq
        return success(fact(:not_required, [:no_participant_orders], [])) if orders.empty?

        demand = required_demand(orders)
        return success(fact(:not_required, [:no_inventory_required], [])) if demand.empty?

        rows = reservation_rows(orders)
        verdicts = demand.map { |d| item_fact(d, rows) }
        reasons = verdicts.flat_map { |v| v[:reasons] }.uniq
        verdict = aggregate(verdicts, orders)

        items = demand.each_with_index.map do |d, i|
          { order_id: d[:order].prefixed_id,
            line_item_id: d[:line_item].prefixed_id,
            quantity: d[:quantity],
            verdict: verdicts[i][:verdict] }
        end

        success(fact(verdict, reasons, items))
      end

      private

      def fact(verdict, reasons, items)
        { verdict: verdict, reasons: reasons, items: items }
      end

      def required_demand(orders)
        orders.flat_map do |order|
          order.line_items.filter_map do |li|
            next unless PallasTrade::Stock::InventoryRequirement.required?(li)

            { order: order, line_item: li, quantity: li.quantity }
          end
        end
      end

      # 交易参与订单上的全部 reservation 行（含 legacy 未绑定 txn 的行）
      def reservation_rows(orders)
        PallasTrade::StockReservation.where(order_id: orders.map(&:id)).to_a
      end

      def rows_for(rows, order_id, line_item_id)
        rows.select { |r| r.order_id == order_id && r.line_item_id == line_item_id }
      end

      # 单个 demand 行的事实
      def item_fact(demand, rows)
        rows = rows_for(rows, demand[:order].id, demand[:line_item].id)
        qty = demand[:quantity]

        committed_qty = rows.select { |r| r.state == 'committed' }.sum(&:quantity)
        reserved_qty = rows.select { |r| r.state == 'reserved' && r.expires_at > Time.current }.sum(&:quantity)
        has_released = rows.any? { |r| r.state == 'released' }
        has_expired = rows.any? { |r| r.state == 'expired' }

        if committed_qty >= qty
          order_completed = demand[:order].completed?
          return { verdict: :committed, reasons: [:committed_covered, order_completed ? :order_completed : :order_incomplete] }
        end
        return { verdict: :reserved, reasons: [:reserved_covered] } if reserved_qty >= qty

        if has_released && !has_expired
          { verdict: :released, reasons: [:released_without_coverage] }
        elsif has_expired
          { verdict: :expired, reasons: [:expired_without_coverage] }
        elsif committed_qty.positive? || reserved_qty.positive?
          { verdict: :ambiguous, reasons: [:partial_coverage] }
        else
          { verdict: :unreserved, reasons: [:no_reservation] }
        end
      end

      # 汇总：终态不一致/异常态优先暴露，正常态给最高级覆盖（committed > reserved）。
      def aggregate(verdicts, _orders)
        v = verdicts.map { |x| x[:verdict] }
        return :ambiguous if v.any?(:ambiguous)
        return :released if v.any?(:released)
        return :expired if v.any?(:expired)
        return :unreserved if v.any?(:unreserved)

        # committed + reserved 混合（组合部分未完成消费）→ AMBIGUOUS（PAID 侧交 Recovery 逐项处理）
        return :ambiguous if v.include?(:committed) && v.include?(:reserved)
        return :committed if v.all?(:committed)

        :reserved
      end
    end
  end
end
