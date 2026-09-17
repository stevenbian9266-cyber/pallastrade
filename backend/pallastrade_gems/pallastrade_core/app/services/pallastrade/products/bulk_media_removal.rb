# frozen_string_literal: true

module PallasTrade
  module Products
    # 批量移除媒体（方案 §5.1「Bulk Operations 2.0」的 Media 行；
    # PRD-20260917-catalog-bulk-media）。
    #
    # ## 范围（与 i18n 文案口径一致，不留歧义）
    #
    # 选中商品的**全部媒体**：
    #   ① 商品级 `product.media`      → `Asset` where `viewable_type = 'PallasTrade::Product'`
    #   ② 该商品**所有变体（含 master）**的 `variant.images`
    #                                 → `Asset` where `viewable_type = 'PallasTrade::Variant'`
    #
    # 这是「清空这个商品的媒体」，与「批量替换 / 批量生成」无关（方案明确 Media 只做移除）。
    #
    # ## 级联与指针（最容易做错的两处）
    #
    # - **级联不重建**：`PallasTrade::Asset` 自带
    #   `has_many :variant_media, dependent: :destroy`，所以变体↔媒体的关联行随 Asset
    #   一起清理，并触发 `VariantMedia#after_commit :refresh_variant_thumbnail`。
    #   本服务**不**手写第二套级联（手写反而会漏掉缩略图刷新）。
    # - **指针必须手动清**：`Product#primary_media_id` 与 `Variant#primary_media_id` 都
    #   **没有** `dependent:`，删完必须把受影响记录的该列置 `nil`，否则留下悬空外键。
    #
    # ## 与 Catalog Health 的关系
    #
    # Catalog Health 的 `missing_media` 口径是「**产品层与变体层都没有资产**」
    # （见 `ai/skills/pallastrade-admin/SKILL.md`）。因此清空后这些商品会**自然出现在
    # Catalog Health 待办里** —— 这正是本动作的预期闭环：先清掉错的，再从待办里重传。
    class BulkMediaRemoval < BulkOperation
      PRODUCT_TYPE = 'PallasTrade::Product'
      VARIANT_TYPE = 'PallasTrade::Variant'

      private

      def run(dry_run:)
        warnings = Hash.new(0)

        # `bulk_collection` 已按 `:update` 过滤，所以这里单独判的是「能改商品但不能管媒体」
        unless ability.can?(:manage, PallasTrade::Asset)
          warnings[:media_permission_denied] += 1
          return result(0, products.size, warnings)
        end

        product_ids = products.map(&:id)
        variant_ids = PallasTrade::Variant.where(product_id: product_ids).pluck(:id)

        updated = media_holder_ids(product_ids, variant_ids).size
        skipped = product_ids.size - updated

        unless dry_run
          assets = asset_scope(product_ids, variant_ids).to_a
          # `destroy` 而不是 `delete_all`：需要回调来清理 ActiveStorage 附件，
          # 并借 Asset 自带的 dependent 删除 variant_media 关联。
          PallasTrade::Asset.destroy(assets.map(&:id)) if assets.any?

          clear_primary_media!(product_ids, variant_ids)
        end

        result(updated, skipped, warnings)
      end

      # 商品级或任一变体级有媒体的商品 id（去重）。
      def media_holder_ids(product_ids, variant_ids)
        ids = PallasTrade::Asset
              .where(viewable_type: PRODUCT_TYPE, viewable_id: product_ids)
              .distinct.pluck(:viewable_id)

        if variant_ids.any?
          variant_holder_ids = PallasTrade::Asset
                               .where(viewable_type: VARIANT_TYPE, viewable_id: variant_ids)
                               .distinct.pluck(:viewable_id)

          if variant_holder_ids.any?
            ids += PallasTrade::Variant.where(id: variant_holder_ids).distinct.pluck(:product_id)
          end
        end

        ids.uniq
      end

      def asset_scope(product_ids, variant_ids)
        relation = PallasTrade::Asset.where(viewable_type: PRODUCT_TYPE, viewable_id: product_ids)
        return relation if variant_ids.empty?

        relation.or(PallasTrade::Asset.where(viewable_type: VARIANT_TYPE, viewable_id: variant_ids))
      end

      def clear_primary_media!(product_ids, variant_ids)
        PallasTrade::Product
          .where(id: product_ids).where.not(primary_media_id: nil)
          .update_all(primary_media_id: nil, updated_at: Time.current)

        PallasTrade::Variant
          .where(id: variant_ids).where.not(primary_media_id: nil)
          .update_all(primary_media_id: nil, updated_at: Time.current)
      end
    end
  end
end
