# frozen_string_literal: true

module PallasTrade
  module Products
    # 撤销商品合并（D-3 切片1, PRD-20260916-catalog-d3-product-merge FR-010/FR-011）。
    #
    # 只读台账：把台账里记下的**每一条**迁移逐条搬回被合并商品，恢复它的状态与可见性，
    # 停用本次合并建立的 redirect，并把台账标记为已撤销 —— 同样在单个事务内。
    #
    # 保守原则：任何清单项已经不存在或已易主 → **整体拒绝**（`Blocked`），不做部分撤销 ——
    # 半途状态比"撤销失败"更难收拾。
    class UndoMerge
      # 撤销被阻塞（清单项缺失/易主）
      class Blocked < StandardError
        attr_reader :blockers

        def initialize(blockers)
          @blockers = blockers
          super("merge cannot be undone: #{blockers.size} blocking item(s)")
        end
      end

      Result = Struct.new(:ledger, :restored, :already_undone, keyword_init: true) do
        def already_undone? = already_undone
      end

      # 每段：模型 → 归属外键（+ 可选期望值）
      SECTIONS = {
        'variants' => [PallasTrade::Variant, :product_id],
        'reviews' => [PallasTrade::Review, :product_id],
        'media' => [PallasTrade::Asset, :viewable_id],
        'classifications' => [PallasTrade::Classification, :product_id],
        'promotions' => [PallasTrade::ProductPromotionRule, :product_id],
        'master_stock' => [PallasTrade::StockItem, :variant_id]
      }.freeze

      def self.call(store:, merge:, actor: nil) = new(store:, merge:, actor:).call

      def initialize(store:, merge:, actor: nil)
        @store = store
        @merge = merge
        @actor = actor
      end

      attr_reader :store, :merge, :actor

      def call
        # 幂等：已撤销 → 原样回答，不产生新写入。
        return Result.new(ledger: merge, restored: {}, already_undone: true) if merge.undone?

        blockers = collect_blockers
        raise Blocked, blockers if blockers.any?

        PallasTrade::ProductMerge.transaction do
          restored = reverse_moves
          deactivate_redirects
          restore_absorbed
          mark_undone
          record_audit(restored)

          Result.new(ledger: merge.reload, restored: restored, already_undone: false)
        end
      end

      private

      def survivor = merge.survivor
      def absorbed = merge.absorbed

      def collect_blockers
        merge.moved.flat_map do |section, ids|
          klass, foreign_key = SECTIONS.fetch(section, [nil, nil])
          next [] if klass.nil?

          Array(ids).filter_map { |id| blocker_for(klass, foreign_key, id, section) }
        end
      end

      def blocker_for(klass, foreign_key, id, section)
        record = klass.find_by(id: id)
        return { section: section, id: id, reason: 'missing' } if record.nil?

        expected = section == 'master_stock' ? master_variant_of(survivor)&.id : survivor.id
        actual = record.public_send(foreign_key)
        return { section: section, id: id, reason: 'moved_elsewhere', actual: actual } if actual != expected

        nil
      end

      # 显式查询：不依赖实例上可能陈旧的 `master` 关联缓存。
      def master_variant_of(product)
        @master_variant_ids ||= {}
        @master_variant_ids[product.id] ||= PallasTrade::Variant.where(product_id: product.id, is_master: true).pick(:id)
      end

      def reverse_moves
        restored = {}

        merge.moved.each do |section, ids|
          klass, = SECTIONS.fetch(section, [nil, nil])
          next if klass.nil?

          # 用**关联对象**赋值（而不是 `_id`）：多态 `viewable` 与 `product` 都有 presence 校验，
          # 赋 id 会留下空关联缓存 → 校验失败。
          case section
          when 'media'
            Array(ids).each_slice(500) do |slice|
              PallasTrade::Asset.where(id: slice).find_each { |asset| asset.update!(viewable: absorbed) }
            end
          when 'master_stock'
            master = master_variant_of(absorbed)
            Array(ids).each_slice(500) do |slice|
              PallasTrade::StockItem.where(id: slice).find_each { |item| item.update!(variant_id: master) }
            end
          else
            Array(ids).each_slice(500) do |slice|
              klass.where(id: slice).find_each { |record| record.update!(product: absorbed) }
            end
          end

          restored[section] = Array(ids)
        end

        restored
      end

      # 保留规则本身（历史事实），只停用 —— 商家仍能在 Redirect 后台看到它。
      def deactivate_redirects
        ids = Array(merge.redirect_ids)
        return if ids.empty?

        PallasTrade::Redirect.where(id: ids).update_all(active: false, updated_at: Time.current)
      end

      def restore_absorbed
        absorbed.restore if absorbed.deleted? # acts_as_paranoid 反软删
        restore_status!
        absorbed.update!(private_metadata: (absorbed.private_metadata || {}).except('merged_into'))
      end

      # 恢复合并前的状态；状态机不接受时退回 activate（可见性优先于精确状态）。
      def restore_status!
        status = merge.absorbed_status_before.presence
        return if status.blank? || absorbed.status == status

        absorbed.update(status: status)
        absorbed.activate! if absorbed.persisted? && absorbed.status != status && absorbed.can_activate?
      rescue StandardError
        absorbed.activate! if absorbed.can_activate?
      end

      def mark_undone
        merge.update!(
          undone_at: Time.current,
          undone_by_label: actor_label
        )
      end

      def record_audit(restored)
        PallasTrade::Audit.record(
          action: 'product_merge_undone',
          actor: actor.present? ? { type: actor.class.name, id: actor.id, label: actor_label } : 'system',
          resource: survivor,
          after: {
            'merge_id' => merge.prefixed_id,
            'restored' => restored.transform_values(&:size),
            'absorbed_id' => absorbed.prefixed_id
          }
        )
      rescue StandardError
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
