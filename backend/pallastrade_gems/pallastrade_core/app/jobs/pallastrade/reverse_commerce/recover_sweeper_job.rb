# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8i (PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling)
#
# ReverseCommerce::RecoverSweeperJob —— 保守的 restock-AMBIGUOUS 收敛 sweeper（sidekiq-cron */5）。
# 设计（镜像 Refunds::RecoverSweeperJob / Transactions::RecoverSweeperJob 保守哲学）：
#   - 候选查询：ReturnItem.accepted（store 归属经 inventory_unit→order）LEFT JOIN stock_movements
#     （return_item_id IS NULL——8e 幂等键语义）→ 逐条 restock_eligible? + RestockFact.resolve == AMBIGUOUS
#     复核 → 收集 order ids（去重）→ 每订单 enqueue RecoverJob（幂等，重复安全）
#   - capped（max_enqueues，默认 20）：超出仅计数 + warn（防风暴；周期重扫）
#   - 只 enqueue，不做任何资金/库存副作用（Recover 自身幂等）
module PallasTrade
  module ReverseCommerce
    class RecoverSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      DEFAULT_MAX_ENQUEUES = 20

      # @param store_id [Integer, nil] 限定单店（默认全店扫描）
      # @param max_enqueues [Integer] 每轮最多 enqueue 的订单数（防风暴）
      def perform(store_id: nil, max_enqueues: DEFAULT_MAX_ENQUEUES)
        stores = store_id ? [PallasTrade::Store.find_by(id: store_id)].compact : PallasTrade::Store.all.to_a

        found_orders = 0
        enqueued = 0
        capped = 0
        per_store = {}

        stores.each do |store|
          order_ids = ambiguous_order_ids(store)
          per_store[store.code] = order_ids.size
          found_orders += order_ids.size

          order_ids.each do |order_id|
            if enqueued >= max_enqueues.to_i
              capped += 1
              next
            end
            PallasTrade::ReverseCommerce::RecoverJob.perform_later(order_id)
            enqueued += 1
          end
        end

        payload = {
          event: 'reverse_commerce.recover_sweeper',
          store_id: store_id,
          found_ambiguous_orders: found_orders,
          enqueued: enqueued,
          capped: capped,
          per_store: per_store,
          max_enqueues: max_enqueues.to_i
        }
        Rails.logger.info(payload.to_json)
        return unless capped.positive? || found_orders > enqueued

        Rails.logger.warn("[ReverseCommerce::RecoverSweeperJob] capped_or_overflow #{payload.to_json}")
      end

      private

      # store 内「accepted + restock_eligible + 无 StockMovement(return_item_id)」的订单（去重）。
      # 候选查询走 SQL（LEFT JOIN 幂等键），eligible/resolve 逐条 Ruby 复核（权威、不猜）。
      def ambiguous_order_ids(store)
        items = PallasTrade::ReturnItem.accepted
                        .joins(inventory_unit: :order)
                        .where(pallastrade_orders: { store_id: store.id })
                        .joins('LEFT JOIN pallastrade_stock_movements sm ' \
                               'ON sm.return_item_id = pallastrade_return_items.id')
                        .where(sm: { id: nil })

        ids = []
        items.find_each do |item|
          next unless item.restock_eligible?
          next unless PallasTrade::Returns::RestockFact.resolve(return_item: item) == PallasTrade::Returns::RestockFact::AMBIGUOUS

          ids << item.inventory_unit.order_id
        end
        ids.uniq
      end
    end
  end
end
