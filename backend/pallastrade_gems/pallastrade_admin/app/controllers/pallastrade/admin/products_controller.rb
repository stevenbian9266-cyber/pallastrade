module PallasTrade
  module Admin
    class ProductsController < ResourceController
      include PallasTrade::Admin::StockLocationsHelper
      include PallasTrade::Admin::BulkOperationsConcern
      include PallasTrade::Admin::AssetsHelper

      helper 'pallastrade/admin/products'
      helper 'pallastrade/admin/taxons'

      before_action :load_data, except: :index
      before_action :load_variants_data, only: %i[edit update]
      before_action :set_product_defaults, only: :new
      # 面包屑由导航自动推导（P3）：Products；编辑页追加产品名
      before_action :add_breadcrumb_for_product, only: [:edit, :update]

      before_action :prepare_product_params, only: [:create, :update]
      before_action :strip_stock_items_param, only: [:create, :update]
      before_action :check_slug_availability, only: [:create, :update]

      new_action.before :build_master_prices
      new_action.before :build_master_stock_items
      edit_action.before :build_master_prices
      edit_action.before :build_master_stock_items
      create.after :assign_session_uploaded_assets
      update.before :skip_updating_status
      update.before :update_status
      update.before :remove_empty_params
      helper_method :clone_object_url

      # https://blog.corsego.com/hotwire-turbo-streams-autocomplete-search
      def search
        query = params[:q]&.strip

        head :ok and return if query.blank? || query.length < 3

        scope = current_store.products.not_archived.accessible_by(current_ability, :index)
        scope = scope.where.not(id: params[:omit_ids].split(',')) if params[:omit_ids].present?
        @products = scope.includes(:primary_media).search(query).limit(params[:limit] || 10)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace(
                'products_search_results',
                partial: 'pallastrade/admin/products/search_results',
                locals: { products: @products }
              )
            ]
          end
        end
      end

      def show
        redirect_to action: :edit
      end

      def update
        invoke_callbacks(:update, :before)
        # Product history（PRD-20260915-catalog-batch-d1-product-history）：
        # 先取快照，成功后再记录差异（只存真正变化的字段）。
        history_before = PallasTrade::ProductHistory::Recorder.snapshot(@product)

        success = ActiveRecord::Base.transaction do
          @prepare_params_service&.variants_to_discontinue&.each(&:discontinue!)

          unless @product.update(permitted_resource_params)
            raise ActiveRecord::Rollback
          end

          true
        end

        if success
          set_current_store
          invoke_callbacks(:update, :after)
          record_product_history('product.updated', before: history_before, metadata: nested_history_metadata)
          flash[:success] = flash_message_for(@product, :successfully_updated)
          redirect_to location_after_save
        else
          # Stops people submitting blank slugs, causing errors when they try to
          # update the product again
          @product.slug = @product.slug_was if @product.slug.blank?
          invoke_callbacks(:update, :fails)
          render :edit, status: :unprocessable_content
        end
      end

      def clone
        clone_result = @product.duplicate

        if clone_result.success?
          flash[:success] = PallasTrade.t('notice_messages.product_cloned')
          redirect_to PallasTrade.edit_admin_product_path(clone_result.value)
        else
          flash[:error] = PallasTrade.t('notice_messages.product_not_cloned', error: clone_result.error.value)
          redirect_to PallasTrade.edit_admin_product_path(@product)
        end
      end

      def bulk_status_update
        bulk_collection.update_all(status: params[:status], updated_at: Time.current)
        bulk_collection.each(&:enqueue_search_index) # reindex products
        invoke_callbacks(:bulk_status_update, :after)
        record_bulk_history('product.bulk_status_updated', metadata: { 'status' => params[:status] })

        handle_bulk_operation_response
      end

      def bulk_remove_from_taxons
        taxons = current_store.taxons.accessible_by(current_ability, :manage).where(id: params[:taxon_ids])
        PallasTrade::Taxons::RemoveProducts.call(taxons: taxons, products: bulk_collection)
        PallasTrade::Product.bulk_auto_match_taxons(current_store, bulk_collection.ids)

        handle_bulk_operation_response
      end

      def bulk_add_to_taxons
        taxons = current_store.taxons.accessible_by(current_ability, :manage).where(id: params[:taxon_ids])
        PallasTrade::Taxons::AddProducts.call(taxons: taxons, products: bulk_collection)
        PallasTrade::Product.bulk_auto_match_taxons(current_store, bulk_collection.ids)

        handle_bulk_operation_response
      end

      # PRD-20260915-admin-bulk-operations-2（批量运营 2.0）：
      # 每个动作先经 `*_preview`（零写入：将更新/将跳过/警告），确认后执行。
      def bulk_price_preview
        render_bulk_preview(
          bulk_price_update,
          path: pallastrade.bulk_update_price_admin_products_path,
          fields: bulk_preview_fields('ids[]', 'mode', 'currency', 'amount', 'percent')
        )
      end

      def bulk_update_price
        run_bulk_operation(
          bulk_price_update,
          'admin.bulk_ops.products.result.price_updated',
          history_action: 'product.bulk_price_updated'
        )
      end

      def bulk_inventory_preview
        render_bulk_preview(
          bulk_inventory_adjust,
          path: pallastrade.bulk_adjust_inventory_admin_products_path,
          fields: bulk_preview_fields('ids[]', 'stock_location_id', 'delta')
        )
      end

      def bulk_adjust_inventory
        run_bulk_operation(
          bulk_inventory_adjust,
          'admin.bulk_ops.products.result.inventory_updated',
          history_action: 'product.bulk_inventory_adjusted'
        )
      end

      def bulk_channels_preview
        render_bulk_preview(
          bulk_channel_assignment,
          path: pallastrade.bulk_update_channels_admin_products_path,
          fields: bulk_preview_fields('ids[]', 'mode', 'channel_ids[]')
        )
      end

      def bulk_update_channels
        run_bulk_operation(
          bulk_channel_assignment,
          'admin.bulk_ops.products.result.channels_updated',
          history_action: 'product.bulk_channels_updated'
        )
      end

      # PRD-20260917-catalog-bulk-media：批量移除媒体（方案 §5.1 Bulk Media）。
      # 与其它破坏性批量同样走「预览（零写入）→ 确认 → 执行」，不提供直接执行入口。
      def bulk_media_preview
        render_bulk_preview(
          bulk_media_removal,
          path: pallastrade.bulk_media_remove_admin_products_path,
          fields: bulk_preview_fields('ids[]')
        )
      end

      def bulk_media_remove
        run_bulk_operation(
          bulk_media_removal,
          'admin.bulk_ops.products.result.media_removed',
          history_action: 'product.bulk_media_removed'
        )
      end

      def select_options
        render json: current_store.products.not_archived.accessible_by(current_ability, :index).to_tom_select_json
      end

      protected

      def find_resource
        current_store.products.accessible_by(current_ability, :manage).friendly.find(params[:id])
      end

      def load_data
        @taxons = Taxon.order(:name)
        @option_types = OptionType.order(:name)
        @tax_categories = TaxCategory.order(:name)
        @shipping_categories = ShippingCategory.order(:name)
      end

      def load_variants_data
        return unless @product.has_variants?

        @product_options = {}
        @product_available_options = {}

        @product.
          option_values.
          joins(option_type: :product_option_types).
          includes(option_type: :option_values).
          merge(@product.product_option_types).
          reorder("#{PallasTrade::ProductOptionType.table_name}.position", "#{PallasTrade::Variant.table_name}.position").
          uniq.group_by(&:option_type).each_with_index do |option, index|
            option_type, option_values = option

            @product_options[option_type.prefixed_id] = {
              name: option_type.presentation,
              position: index + 1,
              values: option_values.map { |ov| { value: ov.name, text: ov.presentation } }.uniq
            }

            @product_available_options[option_type.prefixed_id] = option_type.option_values.map { |ov| { id: ov.name, name: ov.presentation } }.uniq
          end

        @product_stock = {}
        @product.stock_items.includes(:variant).each do |stock_item|
          @product_stock[stock_item.variant.human_name] ||= {}
          @product_stock[stock_item.variant.human_name][stock_item.stock_location_id.to_s] = {
            count_on_hand: stock_item.count_on_hand,
            backorderable: stock_item.backorderable,
            id: stock_item.id.to_s
          }
        end

        @product_prices = {}
        @product.prices.base_prices.includes(:variant).each do |price|
          @product_prices[price.variant.human_name] ||= {}
          @product_prices[price.variant.human_name][price.currency.downcase] = {
            id: price.id.to_s,
            amount: price.amount
          }
        end

        @product_variant_ids = {}
        @product_variant_prefix_ids = {}
        @product_variant_images = {}

        @product.variants.includes(:option_values, primary_media: { attachment_attachment: :blob }).each do |variant|
          @product_variant_ids[variant.human_name] = variant.id.to_s
          @product_variant_prefix_ids[variant.human_name] = variant.to_param

          image = variant.primary_media || @product.primary_media
          if image.present? && image.attached? && image.variable?
            @product_variant_images[variant.human_name] = helpers.pallastrade_image_url(image, variant: :mini)
          end
        end
      end

      def set_product_defaults
        @product.shipping_category ||= @shipping_categories&.first
      end

      def skip_updating_status
        @new_status = params[:product].delete(:status)
      end

      def update_status
        return if @new_status == @product.status
        return if cannot?(:activate, @product) && @new_status&.to_sym == :active

        event_to_fire = @product.status_transitions.find { |transition| transition.from == @product.status && transition.to == @new_status }&.event
        @product.status_event = event_to_fire if event_to_fire
      end

      def remove_empty_params
        reject_empty_params(:tag_list) if can?(:manage_tags, @product)
        reject_empty_params(:taxon_ids)
        reject_empty_params(:label_list) if can?(:manage_labels, @product)
      end

      def reject_empty_params(key)
        params[:product][key] = params[:product][key].present? ? params[:product][key].reject(&:empty?) : []
      end

      def prepare_product_params
        @prepare_params_service = PallasTrade::Products::PrepareNestedAttributes.new(@product, current_store, permitted_resource_params, current_ability)
        params[:product] = @prepare_params_service.call
      end

      # These includes are not picked automatically by ar_lazy_preload gem so we need to specify them manually.
      def collection_default_sort
        'name asc'
      end

      # Catalog Health drill-down (PRD-20260915-admin-catalog-health-v1, FR-002):
      # `/admin/products?health_issue=missing_media` reuses the very scopes the
      # worklist counts with, so the list length always matches the number the
      # merchant clicked. Unknown keys are ignored (no filtering, no banner).
      def scope
        base_scope = super
        health_issue = params[:health_issue].presence
        return base_scope unless health_issue && PallasTrade::CatalogHealth::Issues.valid_filter?(health_issue)

        PallasTrade::CatalogHealth::Issues.product_relation(base_scope, health_issue, store: current_store) || base_scope
      end

      def collection_includes
        {
          primary_media: [attachment_attachment: :blob],
          stock_items: [],
          master: [:prices, :stock_items],
          variants: [:prices, :stock_items]
        }
      end

      def clone_object_url(resource)
        clone_admin_product_url resource
      end

      # 对象页面包屑：Products > 产品名（P3，原 ProductsBreadcrumbConcern）
      def add_breadcrumb_for_product
        return unless @product.present?
        return if @product.new_record?
        add_breadcrumb @product.name, PallasTrade.edit_admin_product_path(@product)
      end

      private

      def after_bulk_tags_change
        PallasTrade::Product.bulk_auto_match_taxons(current_store, bulk_collection.ids)
        bulk_collection.each(&:enqueue_search_index) # reindex products
      end

      def variant_stock_includes
        [:images, { stock_items: :stock_location, option_values: :option_type }]
      end

      def strip_stock_items_param
        if params.dig(:product, :track_inventory) == '0'
          if params.dig(:product, :master_attributes, :stock_items_attributes).present?
            params[:product][:master_attributes][:stock_items_attributes] = {}
          end
          if params.dig(:product, :variants_attributes)
            params[:product][:variants_attributes].each do |_key, variant|
              variant[:stock_items_attributes] = {}
            end
          end
        end
      end

      def build_master_prices
        return if @product.has_variants?

        current_store.supported_currencies_list.each do |currency|
          @product.master.prices.build(currency: currency) unless @product.master.prices.find { |price| price.currency == currency }
        end
      end

      def build_master_stock_items
        return if @product.has_variants?

        available_stock_locations_list(master_stock_items_locations_opts).each do |_name, id|
          @product.master.stock_items.build(stock_location_id: id, count_on_hand: 0) unless @product.master.stock_items.find do |stock_item|
            stock_item.stock_location_id == id
          end
        end
      end

      def master_stock_items_locations_opts
        {}
      end

      def assign_session_uploaded_assets
        uploaded_assets = session_uploaded_assets('PallasTrade::Product')

        return if uploaded_assets.empty?

        uploaded_assets.update_all(viewable_id: @product.id, viewable_type: 'PallasTrade::Product', updated_at: Time.current)
        @product.update_thumbnail!

        clear_session_for_uploaded_assets('PallasTrade::Product')
      end

      def check_slug_availability
        new_slug = permitted_resource_params[:slug]
        permitted_resource_params[:slug] = @product.ensure_slug_is_unique(new_slug)
      end

      # --- 批量运营 2.0（PRD-20260915-admin-bulk-operations-2）---

      def bulk_price_update
        PallasTrade::Products::BulkPriceUpdate.new(
          products: bulk_collection,
          ability: current_ability,
          currency: params[:currency],
          mode: params[:mode],
          amount: params[:amount],
          percent: params[:percent]
        )
      end

      def bulk_inventory_adjust
        PallasTrade::Products::BulkInventoryAdjust.new(
          products: bulk_collection,
          ability: current_ability,
          stock_location: PallasTrade::StockLocation.find_by(id: params[:stock_location_id]),
          delta: params[:delta].to_i
        )
      end

      def bulk_channel_assignment
        PallasTrade::Products::BulkChannelAssignment.new(
          products: bulk_collection,
          ability: current_ability,
          channels: current_store.channels.where(id: params[:channel_ids]),
          mode: params[:mode]
        )
      end

      def bulk_media_removal
        PallasTrade::Products::BulkMediaRemoval.new(
          # 媒体删除**不可逆**，所以这里额外按 current_store 收窄。
          # 注意：共享的 `bulk_collection` 只按 ability 过滤（`accessible_by(...).where(id:)`），
          # 而 superuser 的 ability 是跳店的 —— 其余 bulk 动作同样如此（既有行为，未改）。
          # 合法路径下 ids 本就来自当前店铺的列表，所以此收窄对正常使用是 no-op，
          # 对被篖改的请求则是一道防线。
          products: bulk_collection.merge(current_store.products),
          ability: current_ability
        )
      end

      # Builds hidden-field payload for the confirmation step. Array names keep
      # the `[]` suffix (ids[]), scalar names render a single value.
      def bulk_preview_fields(*names)
        names.index_with { |name| Array(params[name.delete_suffix('[]')]).compact_blank }
      end

      def render_bulk_preview(service, path:, fields:)
        @preview_result = service.preview
        @preview_path = path
        @preview_fields = fields

        render turbo_stream: turbo_stream.replace(
          :bulk_dialog,
          partial: 'pallastrade/admin/bulk_operations/preview'
        )
      end

      def run_bulk_operation(service, message_key, history_action: nil)
        result = service.call

        if history_action
          record_bulk_history(
            history_action,
            metadata: {
              'updated_count' => result.updated_count,
              'skipped_count' => result.skipped_count
            }
          )
        end

        flash[:success] = PallasTrade.t(
          message_key, count: result.updated_count, skipped: result.skipped_count
        )
        handle_bulk_operation_response
      end

      # --- Product history（PRD-20260915-catalog-batch-d1-product-history）---

      def record_product_history(action, before: nil, metadata: {})
        PallasTrade::ProductHistory::Recorder.record_product(
          product: @product,
          action: action,
          actor: try_pallastrade_current_user,
          before: before,
          metadata: metadata
        )
      end

      def record_bulk_history(action, metadata: {})
        PallasTrade::ProductHistory::Recorder.record_bulk(
          products: bulk_collection,
          action: action,
          actor: try_pallastrade_current_user,
          metadata: metadata
        )
      end

      # 表单里改动的嵌套区块（变体/媒体/分类）——时间线只标注「改过哪些区块」。
      def nested_history_metadata
        product_params = params[:product] || {}
        sections = []
        if product_params[:variants_attributes].present? || product_params[:master_attributes].present?
          sections << 'variants'
        end
        sections << 'media' if product_params[:media].present?
        if product_params[:taxon_ids].present? || product_params[:category_ids].present?
          sections << 'categories'
        end

        sections.empty? ? {} : { 'sections' => sections }
      end

      def permitted_resource_params
        @permitted_resource_params ||= begin
          attrs = if cannot?(:activate, @product) && @new_status&.to_sym == :active
                    params.require(:product).permit(permitted_product_attributes).except(:status, :make_active_at)
                  else
                    params.require(:product).permit(permitted_product_attributes)
                  end
          parse_datetime_in_store_timezone(attrs, :available_on, :discontinue_on, :make_active_at)
          parse_datetime_in_store_timezone(attrs[:master_attributes], :preorder_ships_at) if attrs[:master_attributes].present?
          attrs
        end
      end
    end
  end
end
