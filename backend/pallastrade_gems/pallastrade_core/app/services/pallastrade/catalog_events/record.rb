# frozen_string_literal: true

module PallasTrade
  module CatalogEvents
    # 把一批前台商品事件写入旁路表。
    #
    # 设计约束（PRD-20260917-catalog-product-events）：
    # - **幂等**：`(store_id, event_id)` 唯一键 + `ON CONFLICT DO NOTHING`，
    #   客户端重试 / 双发**不会重复计数**。
    # - **零 PII**：只接收 `visitor_id` 用于**服务端**派生摘要，绝不落库原值；
    #   不接受任何自由 `metadata`（避免绕过白名单塞入任意数据）。
    # - **常数代价**：一次批量 INSERT + 一次 HMAC，无外部调用、无 N+1、不入队。
    # - **旁路**：不触发任何事件 / 订阅者，不影响任何业务状态。
    class Record
      # @param store [PallasTrade::Store]
      # @param events [Array<Hash>] 已通过控制器白名单的事件数组
      # @param visitor_id [String] 请求级访客标识（同一次 flush 共用）
      def self.call(store:, events:, visitor_id:)
        new(store: store, events: events, visitor_id: visitor_id).call
      end

      def initialize(store:, events:, visitor_id:)
        @store = store
        @events = events
        @visitor_id = visitor_id
      end

      # @return [Integer] 本批**有效事件数**（重复的 event_id 被幂等忽略，不单独计数）
      def call
        rows = build_rows
        return 0 if rows.empty?

        PallasTrade::CatalogEvent.insert_all(
          rows,
          unique_by: :idx_catalog_events_idempotency
        )

        rows.size
      end

      private

      attr_reader :store, :events, :visitor_id

      def build_rows
        now = Time.current
        session_hash = PallasTrade::CatalogEvent.digest_visitor(visitor_id, store)
        return [] if session_hash.blank?

        events.filter_map do |event|
          event_name = event[:event_name].to_s
          next unless PallasTrade::CatalogEvent::EVENT_NAMES.include?(event_name)

          event_id = event[:event_id].to_s.strip
          next if event_id.blank?

          {
            store_id: store.id,
            event_id: event_id,
            event_name: event_name,
            product_id: resolve_product_id(event[:product_id]),
            variant_id: resolve_variant_id(event[:variant_id]),
            list_id: presence(event[:list_id]),
            list_name: presence(event[:list_name]),
            position: integer_or_nil(event[:position]),
            session_hash: session_hash,
            occurred_at: occurred_at_for(event[:occurred_at], now),
            # 追加写：只有 created_at（无需 updated_at）
            created_at: now
          }
        end
      end

      # 解析前缀商品 ID（`prod_…`），且**必须属于当前店铺**——否则视为无商品，
      # 不因一个坏 ID 丢掉整批事件。
      def resolve_product_id(raw)
        value = presence(raw)
        return nil if value.nil?

        return value.to_i if value.match?(/\A\d+\z/)

        product = store.products.find_by_prefix_id(value) if PallasTrade::PrefixedId.prefixed_id?(value)
        product&.id
      rescue StandardError
        nil
      end

      # 变体 ID：数字形式用 `find_by` 校验归属；前缀形式直接解析。
      def resolve_variant_id(raw)
        value = presence(raw)
        return nil if value.nil?

        variant = if value.match?(/\A\d+\z/)
                    store.variants.find_by(id: value.to_i)
                  elsif PallasTrade::PrefixedId.prefixed_id?(value)
                    PallasTrade::Variant.find_by_prefix_id(value)
                  end

        variant&.id
      rescue StandardError
        nil
      end

      # 客户端时钟不可信：超出合理窗口（过去保留期 √ 未来 5 分钟）一律记服务端时间。
      def occurred_at_for(raw, now)
        parsed = Time.zone.parse(raw.to_s)
        return now if parsed.nil?

        earliest = PallasTrade::CatalogEvent::RETENTION_DAYS.days.ago
        return now if parsed < earliest || parsed > (now + 5.minutes)

        parsed
      rescue ArgumentError, TypeError
        now
      end

      def presence(value)
        string = value.to_s.strip
        string.empty? ? nil : string
      end

      def integer_or_nil(value)
        return nil if value.nil? || value.to_s.strip.empty?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
