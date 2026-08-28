module PallasTrade
  module Api
    module V3
      module Admin
        class OrdersController < ResourceController
          include PallasTrade::Api::V3::OrderLock

          scoped_resource :orders

          skip_before_action :set_resource, only: [:index, :create]
          before_action :set_resource, only: [:show, :update, :destroy, :complete, :cancel, :approve, :resume, :resend_confirmation, :split]

          # POST /api/v3/admin/orders
          def create
            authorize!(:create, PallasTrade::Order)

            result = PallasTrade.order_create_service.call(
              store: current_store,
              user: resolve_user,
              params: order_create_params
            )

            if result.success?
              @resource = result.value
              render json: serialize_resource(@resource), status: :created
            else
              render_service_error(result.error)
            end
          end

          # PATCH /api/v3/admin/orders/:id
          def update
            with_order_lock do
              result = PallasTrade.order_update_service.call(
                order: @resource,
                params: order_update_params
              )

              if result.success?
                render json: serialize_resource(result.value)
              else
                render_validation_error(@resource.errors.presence || result.error)
              end
            end
          end

          # PATCH /api/v3/admin/orders/:id/complete
          def complete
            with_order_lock do
              result = PallasTrade.order_complete_service.call(
                order: @resource,
                payment_pending: ActiveModel::Type::Boolean.new.cast(params[:payment_pending]),
                notify_customer: ActiveModel::Type::Boolean.new.cast(params[:notify_customer])
              )

              if result.success?
                render json: serialize_resource(@resource.reload)
              else
                render_service_error(@resource.errors.presence || result.error, code: ERROR_CODES[:order_cannot_complete])
              end
            end
          end

          # PATCH /api/v3/admin/orders/:id/cancel
          def cancel
            with_order_lock do
              @resource.canceled_by(try_pallastrade_current_user)
              render json: serialize_resource(@resource.reload)
            end
          end

          # PATCH /api/v3/admin/orders/:id/approve
          def approve
            with_order_lock do
              @resource.approved_by(try_pallastrade_current_user)
              render json: serialize_resource(@resource.reload)
            end
          end

          # PATCH /api/v3/admin/orders/:id/resume
          def resume
            with_order_lock do
              @resource.resume!
              render json: serialize_resource(@resource.reload)
            end
          end

          # POST /api/v3/admin/orders/:id/resend_confirmation
          def resend_confirmation
            @resource.publish_event('order.completed')
            render json: serialize_resource(@resource)
          end

          # POST /api/v3/admin/orders/:id/split
          # P6 (2026-08-28)：Admin 手动拆单（flag 灰度）。复用 P2 Orders::Splitter 能力层。
          # body: { groups: { "group_1" => ["li_xxx", ...] }, parent_order_id?, store_id? }
          def split
            with_order_lock do
              unless manual_split_enabled?
                return render_error(code: ERROR_CODES[:record_not_found], message: 'Not found', status: :not_found)
              end

              if split_params[:store_id].present? && !same_store?(split_params[:store_id])
                return render_error(
                  code: ERROR_CODES[:order_cannot_split],
                  message: 'Cross-store split is not supported',
                  status: :unprocessable_content
                )
              end

              result = PallasTrade::Orders::ManualSplit.call(
                order: @resource,
                groups: split_params[:groups].to_unsafe_h || {},
                parent_order: resolve_parent_order(split_params[:parent_order_id])
              )

              if result.success?
                render json: {
                  data: {
                    parent: serialize_resource(@resource.reload),
                    children: serialize_collection(result.value)
                  }
                }
              else
                render_service_error(result.error, code: ERROR_CODES[:order_cannot_split])
              end
            end
          end

          protected

          def model_class
            PallasTrade::Order
          end

          def serializer_class
            PallasTrade.api.admin_order_serializer
          end

          # Override scope — Order uses SingleStoreResource (for_store)
          def scope
            current_store.orders.accessible_by(current_ability, :show).preload_associations_lazily
          end

          def set_resource
            @resource = scope.find_by_prefix_id!(params[:id])
            @order = @resource # needed for OrderLock
            authorize_resource!(@resource)
          end

          # Map state transition actions to :update permission
          def authorize_resource!(resource = @resource, action = action_name.to_sym)
            mapped_action = case action
                            when :complete, :cancel, :approve, :resume, :resend_confirmation, :split
                              :update
                            else
                              action
                            end
            authorize!(mapped_action, resource)
          end

          def collection_includes
            [:line_items, :user, :channel, :rich_text_internal_note]
          end

          private

          def resolve_user
            customer_param = params[:customer_id].presence || params[:user_id].presence
            return unless customer_param

            PallasTrade.user_class.find_by_param!(customer_param)
          end

          # P6：手动拆单 flag——store preference 覆盖 Config，默认关闭
          def manual_split_enabled?
            current_store.preferred_manual_split_enabled.presence || PallasTrade::Config[:admin_manual_split_enabled]
          end

          # P6：store_id 仅允许与源订单同 store（跨店拆单暂不支持）
          def same_store?(store_id)
            numeric = PallasTrade::PrefixedId.decode_prefixed_id(store_id) if store_id.is_a?(String)
            numeric.to_i == current_store.id
          end

          # P6：解析可选 parent_order_id（同 store；缺省由 Splitter 以源订单自身为父）
          def resolve_parent_order(parent_id)
            return if parent_id.blank?

            numeric = PallasTrade::PrefixedId.decode_prefixed_id(parent_id) if parent_id.is_a?(String)
            numeric ? current_store.orders.find_by(id: numeric) : nil
          end

          def split_params
            params.permit(:parent_order_id, :store_id, groups: {})
          end

          def order_create_params
            normalize_params(
              params.permit(
                :email, :customer_id, :user_id, :use_customer_default_address,
                :currency, :market_id, :channel_id, :locale,
                :customer_note, :internal_note,
                :shipping_address_id, :billing_address_id,
                :preferred_stock_location_id,
                :coupon_code,
                metadata: {},
                tags: [],
                shipping_address: address_permitted_keys,
                billing_address: address_permitted_keys,
                items: item_permitted_keys
              )
            )
          end

          def order_update_params
            normalize_params(
              params.permit(
                :email, :customer_id, :user_id,
                :customer_note, :internal_note,
                :currency, :locale, :market_id, :channel_id,
                :preferred_stock_location_id,
                metadata: {},
                tags: [],
                ship_address: address_permitted_keys,
                bill_address: address_permitted_keys,
                items: item_permitted_keys
              )
            )
          end

          def address_permitted_keys
            [
              :firstname, :lastname, :first_name, :last_name,
              :address1, :address2, :city,
              :country_iso, :state_abbr, :country_id, :state_id,
              :zipcode, :postal_code, :phone, :alternative_phone,
              :state_name, :company, :label
            ]
          end

          def item_permitted_keys
            [:variant_id, :quantity, { metadata: {} }]
          end
        end
      end
    end
  end
end
