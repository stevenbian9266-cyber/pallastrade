# frozen_string_literal: true

module PallasTrade
  module StockReservations
    # INV-P3-1/INV-P3-3 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-...):
    # Commit —— Reservation 的**消费事实确认**（RESERVED → COMMITTED）。
    #
    # 领域语义（冻结策略 S7 / INV-I04/I05）：
    #   - COMMITTED 只能在 canonical physical consumption（Order#finalize! → Shipment/
    #     InventoryUnit → StockMovement 扣 count_on_hand）**成功之后**确认；
    #   - 本服务**绝不修改 count_on_hand / 不创建 StockMovement**（第二套扣减被禁止）；
    #   - 幂等：只处理 state=reserved 的行；终态 no-op。重复调用不重复扣库存。
    #
    # 第一阶段（INV-P3-1）作为 primitive 供 canonical 完成路径使用；Transaction 级
    # 编排（guard/coordinator）在 INV-P3-3 接入 Transactions::Finalize。
    class Commit
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @param transaction [PallasTrade::CommerceTransaction, nil] 按 transaction 归属（可选）
      # @return Result success(order | transaction)
      def call(order: nil, transaction: nil)
        scope = PallasTrade::StockReservation.reserved
        scope = scope.where(order_id: order.id) if order
        scope = scope.where(commerce_transaction_id: transaction.id) if transaction

        scope.find_each do |reservation|
          reservation.with_lock do
            reservation.commit! if reservation.state == 'reserved'
          end
        end

        success(order || transaction)
      end
    end
  end
end
