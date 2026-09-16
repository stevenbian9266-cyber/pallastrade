# frozen_string_literal: true

module PallasTrade
  module Products
    # 合并预检（D-3 切片1, PRD-20260916-catalog-d3-product-merge FR-001）。
    #
    # 回答「如果把 absorbed 合并进 survivor，会发生什么」：每一段能搬多少、哪些会被跳过、
    # 旧 URL 会建哪些 301、以及历史交易有多少引用（**只统计，永不改写**）。
    #
    # **只读**：这里没有任何写操作，`Products::Merge` 复用同一份结果执行，
    # 因此「预检说的」与「执行做的」在构造上不可能不一致。
    class MergePreview
      # 一段的可迁移/跳过明细
      Move = Struct.new(:move, :skip, keyword_init: true) do
        def move_count = move.size
        def skip_count = skip.size
        def total = move.size + skip.size
      end

      Result = Struct.new(:survivor, :absorbed, :sections, :historical, :redirects, :warnings,
                          keyword_init: true) do
        # @return [Hash{String=>Hash}] `{ 'variants' => { 'move' => 2, 'skip' => 1 }, ... }`
        # Keys are strings so the same hash can be stored in the ledger (jsonb) and asserted on.
        def counts
          sections.transform_values { |section| { 'move' => section.move_count, 'skip' => section.skip_count } }
                  .transform_keys(&:to_s)
        end

        # @return [Hash{String=>Array<Integer>}] ids to move per section
        def moves = sections.transform_values(&:move)

        # @return [Array<Hash>] every skipped item with its section
        def skipped
          sections.flat_map do |name, section|
            section.skip.map { |item| item.merge(section: name.to_s) }
          end
        end

        def skipped_by_reason
          skipped.group_by { |item| item[:reason] }.transform_values(&:size)
        end

        def total_moved = moves.values.sum(&:size)
        def total_skipped = skipped.size
      end

      def self.call(store:, survivor:, absorbed:) = new(store:, survivor:, absorbed:).call

      def initialize(store:, survivor:, absorbed:)
        @store = store
        @survivor = survivor
        @absorbed = absorbed
      end

      attr_reader :store, :survivor, :absorbed

      def call
        Result.new(
          survivor: survivor,
          absorbed: absorbed,
          sections: {
            variants: variants_section,
            master_stock: master_stock_section,
            reviews: reviews_section,
            media: media_section,
            classifications: classifications_section,
            promotions: promotions_section
          },
          historical: historical_counts,
          redirects: redirect_pairs,
          warnings: warnings
        )
      end

      private

      # 主变体 id。**显式查询**：`product.master` 关联缓存可能陈旧（工厂刚插入的行还没进缓存），
      # 服务对调用方实例的缓存状态毫无控制权，所以一律回数据库。
      def master_variant_id(product)
        @master_variant_ids ||= {}
        @master_variant_ids[product.id] ||= PallasTrade::Variant.where(product_id: product.id, is_master: true).pick(:id)
      end

      # 变体：同 SKU（不分大小写）已经在主商品上 → 跳过，绝不静默覆盖。
      def variants_section
        taken = PallasTrade::Variant.where(product_id: survivor.id, is_master: false)
                                    .where.not(sku: [nil, '']).pluck(:sku).map(&:downcase).to_set
        move = []
        skip = []

        PallasTrade::Variant.where(product_id: absorbed.id, is_master: false).find_each do |variant|
          if variant.sku.present? && taken.include?(variant.sku.downcase)
            skip << { id: variant.id, label: variant.sku, reason: 'sku_conflict' }
          else
            move << variant.id
          end
        end

        Move.new(move: move, skip: skip)
      end

      # 主变体的库存行：同一库存点已有行 → 跳过（**不合并库存数量**，只搬行）。
      def master_stock_section
        taken = PallasTrade::StockItem.where(variant_id: master_variant_id(survivor)).pluck(:stock_location_id).to_set
        move = []
        skip = []

        PallasTrade::StockItem.where(variant_id: master_variant_id(absorbed)).find_each do |item|
          if taken.include?(item.stock_location_id)
            skip << { id: item.id, label: "stock_location:#{item.stock_location_id}", reason: 'stock_location_conflict' }
          else
            move << item.id
          end
        end

        Move.new(move: move, skip: skip)
      end

      # 评论：同一客户已经评过主商品 → 跳过（保留主商品既有的那条）。
      def reviews_section
        taken = PallasTrade::Review.where(product_id: survivor.id).pluck(:user_id).to_set
        move = []
        skip = []

        PallasTrade::Review.where(product_id: absorbed.id).find_each do |review|
          if taken.include?(review.user_id)
            skip << { id: review.id, label: "user:#{review.user_id}", reason: 'review_conflict' }
          else
            move << review.id
          end
        end

        Move.new(move: move, skip: skip)
      end

      # 图片/媒体：只改归属（Asset 是 polymorphic viewable），没有冲突一说。
      def media_section
        move = PallasTrade::Asset.where(viewable_type: 'PallasTrade::Product', viewable_id: absorbed.id).pluck(:id)
        Move.new(move: move, skip: [])
      end

      # 分类：主商品已有同一 taxon → 跳过（重复分类无意义）。
      def classifications_section
        taken = PallasTrade::Classification.where(product_id: survivor.id).pluck(:taxon_id).to_set
        move = []
        skip = []

        PallasTrade::Classification.where(product_id: absorbed.id).find_each do |classification|
          if taken.include?(classification.taxon_id)
            skip << { id: classification.id, label: "taxon:#{classification.taxon_id}", reason: 'taxon_duplicate' }
          else
            move << classification.id
          end
        end

        Move.new(move: move, skip: skip)
      end

      # 促销规则：主商品已挂同一 promotion rule → 跳过（避免重复参与同一促销）。
      # 注意 `pallastrade_product_promotion_rules` 指向的是 **promotion_rule**（promotion 经它再关联）。
      def promotions_section
        taken = PallasTrade::ProductPromotionRule.where(product_id: survivor.id).pluck(:promotion_rule_id).to_set
        move = []
        skip = []

        PallasTrade::ProductPromotionRule.where(product_id: absorbed.id).find_each do |rule|
          if taken.include?(rule.promotion_rule_id)
            skip << { id: rule.id, label: "promotion_rule:#{rule.promotion_rule_id}", reason: 'promotion_duplicate' }
          else
            move << rule.id
          end
        end

        Move.new(move: move, skip: skip)
      end

      # 历史交易的引用**只统计、永不改写**（合并后订单仍指向原来的行项目与变体 id）。
      def historical_counts
        variant_ids = PallasTrade::Variant.where(product_id: absorbed.id).select(:id)

        {
          line_items: PallasTrade::LineItem.where(variant_id: variant_ids).count,
          orders: PallasTrade::Order.joins(:line_items)
                                   .where(pallastrade_line_items: { variant_id: variant_ids })
                                   .distinct.count
        }
      end

      # storefront 的 middleware 拿**完整 pathname**（含 `/{country}/{locale}`）去解析 redirect，
      # 所以每个支持语言都要建一条；国家取店铺默认国家，取不到时退化为基础路径并给出警告。
      def redirect_pairs
        country = store.default_country&.iso&.downcase.presence
        locales = Array(store.supported_locales_list).map(&:to_s).reject(&:blank?)

        prefixes = if locales.empty?
                     [country ? "/#{country}" : '']
                   else
                     locales.map { |locale| country ? "/#{country}/#{locale}" : "/#{locale}" }
                   end

        prefixes.uniq.map do |prefix|
          { from_path: "#{prefix}/products/#{absorbed.slug}", to_path: "#{prefix}/products/#{survivor.slug}" }
        end
      end

      def warnings
        list = []
        list << 'redirect_prefix_assumed' if store.default_country.blank?
        list << 'master_price_not_merged' if absorbed.master.prices.exists?
        list << 'historical_transactions_untouched' if historical_counts[:line_items].positive?
        list
      end
    end
  end
end
