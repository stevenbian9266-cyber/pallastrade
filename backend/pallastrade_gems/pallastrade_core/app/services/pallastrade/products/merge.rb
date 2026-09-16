# frozen_string_literal: true

module PallasTrade
  module Products
    # 商品合并（D-3 切片1, PRD-20260916-catalog-d3-product-merge FR-002/FR-003/FR-009）。
    #
    # 把 `absorbed` 中**可迁移**的引用搬到 `survivor`，建立旧 URL 的 301，把被合并商品归档 +
    # 软删并留下 `merged_into` 标记，最后写台账与审计 —— 全部在**单个事务**内完成。
    #
    # 铁律：**历史交易永不改写**。行项目/订单/支付/交易行仍指向它们当时指向的变体与商品；
    # 合并只改变「商品 → 被引用对象」这一层归属。
    class Merge
      # 失败原因（对外可读，不区分大小写）
      class InvalidMerge < StandardError; end

      Result = Struct.new(:ledger, :preview, :moved, :redirects, keyword_init: true) do
        def already_merged? = ledger.present? && moved.nil?

        def counts = preview&.counts || {}
        def skipped = preview&.skipped || []
        def warnings = preview&.warnings || []
      end

      def self.call(store:, survivor:, absorbed:, actor: nil)
        new(store:, survivor:, absorbed:, actor:).call
      end

      def initialize(store:, survivor:, absorbed:, actor: nil)
        @store = store
        @survivor = survivor
        @absorbed = absorbed
        @actor = actor
      end

      attr_reader :store, :survivor, :absorbed, :actor

      def call
        validate_scope!

        existing = PallasTrade::ProductMerge.active_for(absorbed)
        # 幂等：已经合并过（且未撤销）→ 原样回答，不产生新写入。
        return Result.new(ledger: existing, preview: nil, moved: nil, redirects: []) if existing

        PallasTrade::ProductMerge.transaction do
          preview = MergePreview.call(store: store, survivor: survivor, absorbed: absorbed)
          status_before = absorbed.status
          moved = apply_moves(preview)
          redirects = upsert_redirects(preview)
          mark_absorbed!
          ledger = write_ledger(preview, moved, redirects, status_before)
          record_audit(ledger, preview)

          Result.new(ledger: ledger, preview: preview, moved: moved, redirects: redirects)
        end
      end

      private

      def validate_scope!
        raise InvalidMerge, 'same_product' if survivor.id == absorbed.id
        raise InvalidMerge, 'not_same_store' unless survivor.store_id == store.id && absorbed.store_id == store.id
      end

      # 显式查询：不依赖实例上可能陈旧的 `master` 关联缓存。
      def master_variant_of(product)
        PallasTrade::Variant.where(product_id: product.id, is_master: true).first
      end

      # 逐段迁移。**只迁清单里的 id** —— 与预检共用同一份计算。
      def apply_moves(preview)
        moves = preview.moves
        moved = {}

        Array(moves[:variants]).each_slice(500) do |ids|
          PallasTrade::Variant.where(id: ids).find_each { |variant| variant.update!(product: survivor) }
        end
        moved['variants'] = Array(moves[:variants])

        Array(moves[:master_stock]).each_slice(500) do |ids|
          PallasTrade::StockItem.where(id: ids).find_each { |item| item.update!(variant: master_variant_of(survivor)) }
        end
        moved['master_stock'] = Array(moves[:master_stock])

        Array(moves[:reviews]).each_slice(500) do |ids|
          PallasTrade::Review.where(id: ids).find_each { |review| review.update!(product: survivor) }
        end
        moved['reviews'] = Array(moves[:reviews])

        Array(moves[:media]).each_slice(500) do |ids|
          PallasTrade::Asset.where(id: ids).find_each { |asset| asset.update!(viewable: survivor) }
        end
        moved['media'] = Array(moves[:media])

        Array(moves[:classifications]).each_slice(500) do |ids|
          PallasTrade::Classification.where(id: ids).find_each { |classification| classification.update!(product: survivor) }
        end
        moved['classifications'] = Array(moves[:classifications])

        Array(moves[:promotions]).each_slice(500) do |ids|
          PallasTrade::ProductPromotionRule.where(id: ids).find_each { |rule| rule.update!(product: survivor) }
        end
        moved['promotions'] = Array(moves[:promotions])

        moved
      end

      # 旧 URL → 主商品：一条路径一条规则（幂等 upsert，重复合并不会堆规则）。
      def upsert_redirects(preview)
        preview.redirects.map do |pair|
          redirect = PallasTrade::Redirect.find_or_initialize_by(store: store, from_path: pair[:from_path])
          redirect.to_path = pair[:to_path]
          redirect.active = true
          redirect.save!
          redirect
        end
      end

      # 归档 + **纯软删**。
      # 不用 `destroy`：`Product` 的 `reviews/media/variants` 都是 `dependent: :destroy`，而
      # 这些子记录（尤其是被跳过的评论）并没有 acts_as_paranoid —— 走 destroy 会把它们真删掉。
      # 合并只应改变可见性，不应销毁任何被跳过或未迁移的数据。
      def mark_absorbed!
        absorbed.update!(private_metadata: absorbed_metadata.merge('merged_into' => survivor.prefixed_id))
        absorbed.archive! if absorbed.can_archive?
        absorbed.update_columns(deleted_at: Time.current)
      end

      def write_ledger(preview, moved, redirects, status_before)
        PallasTrade::ProductMerge.create!(
          store: store,
          survivor: survivor,
          absorbed: absorbed,
          actor_label: actor_label,
          moved: moved,
          counts: preview.counts,
          skips: preview.skipped,
          redirect_ids: redirects.map(&:id),
          absorbed_status_before: status_before
        )
      end

      def absorbed_metadata
        (absorbed.private_metadata || {}).except('merged_into')
      end

      def record_audit(ledger, preview)
        PallasTrade::Audit.record(
          action: 'product_merged',
          actor: actor.present? ? { type: actor.class.name, id: actor.id, label: actor_label } : 'system',
          resource: survivor,
          after: {
            'merge_id' => ledger.prefixed_id,
            'absorbed_id' => absorbed.prefixed_id,
            'counts' => preview.counts,
            'skips' => preview.skipped,
            'redirects' => preview.redirects.size
          }
        )
      rescue StandardError
        # 审计失败不应回滚已经完成的合并（与项目既有 try-audit 惯例一致）
        nil
      end

      def actor_label
        return 'system' if actor.blank?

        label = actor.try(:email) || actor.try(:name) || actor.class.name
        "#{label} (#{actor.class.name}##{actor.id})"
      end
    end
  end
end
