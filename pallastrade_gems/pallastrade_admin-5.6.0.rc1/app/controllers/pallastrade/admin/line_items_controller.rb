module PallasTrade
  module Admin
    class LineItemsController < PallasTrade::Admin::ResourceController
      belongs_to 'spree/order', find_by: :prefix_id

      layout 'turbo_rails/frame'

      def create
        @variant = variant_scope.find(params.dig(:line_item, :variant_id))

        @order.transaction do
          line_item_result = create_service.call(order: @order, line_item_attributes: permitted_resource_params)

          if line_item_result.success?
            unless @order.completed?
              max_state = if @order.ship_address.present?
                            @order.ensure_updated_shipments
                            'payment'
                          else
                            'address'
                          end

              result = PallasTrade.checkout_advance_service.call(order: @order, state: max_state)

              unless result.success?
                flash[:error] = result.error.value.full_messages.to_sentence
                raise ActiveRecord::Rollback
              end
            end

            flash[:success] = PallasTrade.t(:successfully_created, resource: PallasTrade.t(:line_item))
          else
            flash[:error] = line_item_result.value.errors.full_messages.to_sentence
            raise ActiveRecord::Rollback
          end
        end

        redirect_to PallasTrade.edit_admin_order_path(@order, line_item_updated: true)
      rescue ActiveRecord::Rollback
        redirect_to PallasTrade.edit_admin_order_path(@order)
      end

      def update
        @order.transaction do
          line_item_result = update_service.call(line_item: @line_item, line_item_attributes: permitted_resource_params)

          if line_item_result.success?
            unless @order.completed?
              max_state = if @order.ship_address.present?
                            @order.ensure_updated_shipments
                            'payment'
                          else
                            'address'
                          end

              result = PallasTrade.checkout_advance_service.call(order: @order, state: max_state)

              unless result.success?
                flash[:error] = result.error.value.full_messages.to_sentence
                raise ActiveRecord::Rollback
              end
            end

            flash[:success] = PallasTrade.t(:successfully_updated, resource: PallasTrade.t(:line_item))
          else
            flash[:error] = line_item_result.value.errors.full_messages.to_sentence
            raise ActiveRecord::Rollback
          end
        end

        redirect_to PallasTrade.edit_admin_order_path(@order, line_item_updated: true)
      rescue ActiveRecord::Rollback
        redirect_to PallasTrade.edit_admin_order_path(@order)
      end

      def destroy
        result = destroy_service.call(line_item: @line_item)
        flash[:success] = PallasTrade.t(:successfully_removed, resource: PallasTrade.t(:line_item)) if result.success?

        redirect_to PallasTrade.edit_admin_order_path(@order, line_item_updated: true)
      end

      def reset_digital_links_limit
        @line_item.digital_links.update_all(access_counter: 0, created_at: Time.current, updated_at: Time.current)
        flash[:success] = PallasTrade.t('admin.successfully_reset_digital_links_limit')

        redirect_to PallasTrade.edit_admin_order_path(@order)
      end

      private

      def model_class
        PallasTrade::LineItem
      end

      def collection_url
        PallasTrade.edit_admin_order_path(@order)
      end

      def update_service
        PallasTrade.line_item_update_service
      end

      def destroy_service
        PallasTrade.line_item_destroy_service
      end

      def create_service
        PallasTrade.line_item_create_service
      end

      def build_resource
        if parent_data.present?
          model_class.new(resource.model_name => parent)
        else
          model_class.new
        end
      end

      def permitted_resource_params
        params.require(:line_item).permit(permitted_line_item_attributes)
      end

      def variant_scope
        PallasTrade::Variant.accessible_by(current_ability, :manage)
      end
    end
  end
end
