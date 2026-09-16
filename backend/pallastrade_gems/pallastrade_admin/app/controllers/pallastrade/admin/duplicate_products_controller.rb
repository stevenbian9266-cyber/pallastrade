# frozen_string_literal: true

module PallasTrade
  module Admin
    # Duplicate Detection V1 (PRD-20260915-catalog-batch-d2-duplicate-detection):
    # the read-only worklist of duplicate product candidates (same barcode, same
    # SKU or same name inside one store) plus a side-by-side comparison so the
    # merchant can decide what to do with them.
    #
    # Merging products is deliberately out of scope — it has to reconcile
    # variants, reviews, redirects and historical transactions (D-3), and the
    # pages here never write.
    class DuplicateProductsController < BaseController
      MAX_COMPARE_PRODUCTS = 6

      def index
        @report = PallasTrade::Products::DuplicateCandidates.new(store: current_store)
        @signal = selected_signal
        @counts = @report.counts
        @candidates = if @signal.present?
                        @report.call.select { |group| group.signal == @signal }
                      else
                        @report.call
                      end
        @recent_merges = PallasTrade::ProductMerge.for_store(current_store).order(created_at: :desc).limit(10)
      end

      # D-3 切片1（PRD-20260916-catalog-d3-product-merge FR-007）：合并预检页。
      # **只读**：先把「会发生什么」摆清楚（每段能搬多少、跳过什么、旧 URL 会建哪些 301），
      # 商家确认后才 POST 执行。
      def merge_preview
        @survivor = scoped_product(params[:survivor_id])
        @absorbed = scoped_product(params[:absorbed_id])

        if @survivor.nil? || @absorbed.nil? || @survivor.id == @absorbed.id
          flash[:error] = PallasTrade.t('admin.duplicate_products.merge.invalid_selection')
          redirect_to pallastrade.admin_duplicate_products_path
          return
        end

        @preview = PallasTrade::Products::MergePreview.call(store: current_store, survivor: @survivor, absorbed: @absorbed)
        @existing_merge = PallasTrade::ProductMerge.active_for(@absorbed)
      end

      # 执行合并：可迁移引用搬到 survivor，旧 URL 301，被合并商品归档 + 软删。
      def merge
        survivor = scoped_product(params[:survivor_id])
        absorbed = scoped_product(params[:absorbed_id])

        result = PallasTrade::Products::Merge.call(
          store: current_store, survivor: survivor, absorbed: absorbed, actor: try_pallastrade_current_user
        )

        flash[:success] = if result.already_merged?
                            PallasTrade.t('admin.duplicate_products.merge.already_merged')
                          else
                            moved = result.ledger.counts.values.sum { |section| section['move'].to_i }
                            PallasTrade.t('admin.duplicate_products.merge.done', count: moved)
                          end
        redirect_to pallastrade.admin_duplicate_products_path
      rescue PallasTrade::Products::Merge::InvalidMerge => e
        flash[:error] = PallasTrade.t('admin.duplicate_products.merge.invalid', reason: e.message)
        redirect_to pallastrade.admin_duplicate_products_path
      end

      # 撤销合并：按台账逐条搬回，并恢复被合并商品的可见性。
      def undo_merge
        merge = PallasTrade::ProductMerge.for_store(current_store).find_by_param!(params[:merge_id])

        PallasTrade::Products::UndoMerge.call(store: current_store, merge: merge, actor: try_pallastrade_current_user)

        flash[:success] = PallasTrade.t('admin.duplicate_products.merge.undone')
        redirect_to pallastrade.admin_duplicate_products_path
      rescue PallasTrade::Products::UndoMerge::Blocked => e
        flash[:error] = PallasTrade.t('admin.duplicate_products.merge.undo_blocked', count: e.blockers.size)
        redirect_to pallastrade.admin_duplicate_products_path
      rescue ActiveRecord::RecordNotFound
        flash[:error] = PallasTrade.t('admin.duplicate_products.merge.not_found')
        redirect_to pallastrade.admin_duplicate_products_path
      end

      def compare
        @products = ordered_comparison_products
        @rows = comparison_rows
      end

      private

      # 只接受本店商品（含已软删：被合并过的商品仍要能查看/撤销）。
      def scoped_product(id)
        return nil if id.blank?

        PallasTrade::Product.with_deleted.where(store_id: current_store.id).find_by_param(id)
      end

      # Anchors CanCan authorization on the product permissions
      # (`PallasTrade::PermissionSets::ProductDisplay` grants read/admin/index),
      # so whoever may see products may see their duplicates.
      def model_class
        PallasTrade::Product
      end

      # @return [String, nil] only a known signal is honoured, anything else is ignored
      def selected_signal
        signal = params[:signal].to_s
        signal.presence if PallasTrade::Products::DuplicateCandidates.valid_signal?(signal)
      end

      # @return [Array<String>] ids as they arrived, capped, so the columns keep order
      def comparison_ids
        Array(params[:product_ids]).map(&:presence).compact.first(MAX_COMPARE_PRODUCTS)
      end

      # @return [Array<PallasTrade::Product>] store-scoped products in the requested order
      def ordered_comparison_products
        ids = comparison_ids
        products = current_store.products.where(id: ids).to_a
        ids.filter_map { |id| products.find { |product| product.id.to_s == id.to_s } }
      end

      # @return [Array<Hash>] `{ label_key:, values: }` rows, one entry per product
      def comparison_rows
        [
          row('name', @products.map(&:name)),
          row('slug', @products.map(&:slug)),
          row('status', @products.map { |product| status_label(product) }),
          row('variants', @products.map { |product| variant_summary(product) }),
          row('barcodes', @products.map { |product| barcode_summary(product) }),
          row('price', @products.map(&:display_price)),
          row('stock', @products.map { |product| product.total_on_hand.to_i }),
          row('channels', @products.map { |product| product.channels.count }),
          row('categories', @products.map { |product| product.categories.count }),
          row('created_at', @products.map { |product| timestamp(product.created_at) }),
          row('updated_at', @products.map { |product| timestamp(product.updated_at) })
        ]
      end

      def row(key, values)
        { label_key: key, values: values.map { |value| value.to_s.presence } }
      end

      def status_label(product)
        PallasTrade.t("admin.duplicate_products.statuses.#{product.status}", default: product.status)
      end

      def variant_summary(product)
        variants = product.variants_including_master
        skus = variants.map(&:sku).reject(&:blank?).uniq
        return variants.size.to_s if skus.empty?

        "#{variants.size} · #{skus.join(', ')}"
      end

      def barcode_summary(product)
        product.variants_including_master.map(&:barcode).reject(&:blank?).uniq.join(', ')
      end

      def timestamp(value)
        value&.strftime('%Y-%m-%d %H:%M')
      end
    end
  end
end
