# frozen_string_literal: true

module PallasTrade
  module CatalogEvents
    # 事件表的保留策略执行器。
    #
    # 事件表是高频追加表，必须有界；本作业**幂等**（重复运行结果一致）且分批删除
    # （避免长事务锁住写入）。默认删除早于 `CatalogEvent::RETENTION_DAYS` 的行。
    #
    # 只删除本表数据，不触碰任何业务表；不需要回滚（数据本就按保留期淘汰）。
    class Prune
      BATCH_SIZE = 5_000

      # @param store [PallasTrade::Store, nil] 传 nil 表示清理所有店铺
      # @param before [Time] 截止时间（早于它的行被删除）
      # @return [Integer] 删除行数
      def self.call(store: nil, before: nil)
        new(store: store, before: before).call
      end

      def initialize(store: nil, before: nil)
        @store = store
        @before = before || PallasTrade::CatalogEvent::RETENTION_DAYS.days.ago
      end

      def call
        deleted = 0

        loop do
          batch = scope.limit(BATCH_SIZE).pluck(:id)
          break if batch.empty?

          deleted += PallasTrade::CatalogEvent.where(id: batch).delete_all
          break if batch.size < BATCH_SIZE
        end

        deleted
      end

      private

      attr_reader :store, :before

      def scope
        relation = PallasTrade::CatalogEvent.where(occurred_at: ...before)
        relation = relation.for_store(store) if store.present?
        relation
      end
    end
  end
end
