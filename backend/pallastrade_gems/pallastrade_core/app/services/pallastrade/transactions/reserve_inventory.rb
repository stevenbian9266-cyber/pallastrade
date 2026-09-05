# frozen_string_literal: true

module PallasTrade
  module Transactions
    # INV-P3-2 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-..., FR-016..021):
    # ReserveInventory —— Transactions::Start 的 Inventory Reserve 阶段（InventoryReservationPort
    # 第一版 application service + StockReservationAdapter，复用 StockReservations::Reserve
    # 为 low-level primitive）。
    #
    # 顺序语义（AC-3001/3002/FR-017/018）：
    #   Snapshot V2 已冻结 → 本服务对全部 participant order 执行 Reserve（幂等，复用悲观锁）
    #   → 把该交易持有的 RESERVED 行绑定 commerce_transaction_id
    #   → 校验每一条 REQUIRED demand 都已有足够 active RESERVED（覆盖"缺货被 Reserve
    #     静默跳过"的窗口）→ 全部成功才允许 PaymentSessions::Start。
    #
    # 失败：返回结构化 INSUFFICIENT_STOCK / INVENTORY_CHANGED，不创建 PaymentSession；
    # 组合/多 participant 部分失败仅补偿**本次 attempt 新建**的 Reservation
    # （created-this-attempt，FR-021）；不释放本次前已合法存在/被复用的行。
    class ReserveInventory
      prepend PallasTrade::ServiceModule::Base

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return Result success(transaction) | failure({ code: 'INSUFFICIENT_STOCK'|'INVENTORY_CHANGED', ... })
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?
        return success(transaction) unless PallasTrade::Config[:stock_reservations_enabled]

        orders = participant_orders(transaction)
        return success(transaction) if orders.empty?

        before_ids = existing_reserved_ids(orders)

        orders.each do |order|
          result = PallasTrade::StockReservations::Reserve.call(order: order)
          next if result.success?

          compensate(transaction, orders, before_ids)
          # FR-037：该 line_item 曾预留且已 EXPIRED → 无法重预留视为 INVENTORY_CHANGED
          code = expired_for_line_item?(orders, result.value) ? 'INVENTORY_CHANGED' : 'INSUFFICIENT_STOCK'
          return failure(transaction, { code: code, message: result.error.to_s })
        end

        # 幂等绑定：本交易新建/复用的 RESERVED 行归属本 transaction（不抢其他 txn 的行）
        bind_to_transaction(transaction, orders)

        # 校验 demand evidence：REQUIRED 的 line_item 必须已有足够 active RESERVED
        missing = missing_demand(orders)
        if missing.any?
          compensate(transaction, orders, before_ids)
          changed = missing.any? { |m| expired_for_line_item?(orders, m[:line_item]) }
          items = missing.map do |m|
            { order_id: m[:order].prefixed_id, line_item_id: m[:line_item].prefixed_id, variant_id: m[:line_item].variant&.prefixed_id }
          end
          return failure(transaction, {
                           code: changed ? 'INVENTORY_CHANGED' : 'INSUFFICIENT_STOCK',
                           message: 'Required inventory could not be reserved',
                           items: items
                         })
        end

        success(transaction)
      end

      private

      def participant_orders(transaction)
        transaction.transaction_orders.includes(:order).filter_map(&:order).uniq
      end

      def existing_reserved_ids(orders)
        PallasTrade::StockReservation.reserved.
          where(order_id: orders.map(&:id)).
          pluck(:id).to_set
      end

      # created-this-attempt 补偿：释放本次新增、仍 RESERVED 的行（保留 RELEASED 历史）；
      # 本次前已存在（被复用）的行不动。
      def compensate(_transaction, orders, before_ids)
        PallasTrade::StockReservation.reserved.
          where(order_id: orders.map(&:id)).
          where.not(id: before_ids.to_a).
          find_each do |reservation|
          reservation.with_lock do
            next unless reservation.state == 'reserved'

            reservation.release_reason = 'reserve_failed_compensation'
            reservation.save! if reservation.release_reason_changed?
            reservation.release!
          end
        end
        # 保险：若补偿后交易仍持有非本次新建行（异常路径），不做强制清理（保留证据，交运维）
      end

      def bind_to_transaction(transaction, orders)
        scope = PallasTrade::StockReservation.reserved.where(order_id: orders.map(&:id))
        scope = scope.where(commerce_transaction_id: [nil, transaction.id])
        scope.update_all(commerce_transaction_id: transaction.id)
      end

      # 返回缺货 REQUIRED 项（订单内 line_item 的 active RESERVED 合计 < 需求量）
      def missing_demand(orders)
        orders.flat_map do |order|
          order.line_items.filter_map do |line_item|
            next unless PallasTrade::Stock::InventoryRequirement.required?(line_item)

            reserved_qty = PallasTrade::StockReservation.reserved.
                           active.
                           where(order_id: order.id, line_item_id: line_item.id).
                           sum(:quantity)
            reserved_qty >= line_item.quantity ? nil : { order: order, line_item: line_item }
          end
        end
      end

      # FR-037：该 line_item 在本交易参与订单上是否曾预留并已 EXPIRED（→ INVENTORY_CHANGED）
      def expired_for_line_item?(orders, line_item)
        return false if line_item.nil?

        PallasTrade::StockReservation.expired_state.
          where(order_id: orders.map(&:id), line_item_id: line_item.id).
          exists?
      end
    end
  end
end
