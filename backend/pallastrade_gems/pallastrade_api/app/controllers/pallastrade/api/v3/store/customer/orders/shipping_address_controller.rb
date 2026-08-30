module PallasTrade
  module Api
    module V3
      module Store
        module Customer
          module Orders
            # 订单模块（PRD-20260829-checkout 收货信息独立填写）：
            # PATCH /api/v3/store/customers/me/orders/:order_id/shipping_address
            # 仅当前登录用户自己的未支付订单可更新收货地址；返回更新后的 Order。
            class ShippingAddressController < Store::BaseController
              prepend_before_action :require_authentication!

              def update
                order = find_editable_order!
                return unless order

                result = PallasTrade::Orders::UpdateShippingAddress.call(
                  order: order,
                  params: permitted_params
                )

                if result.success?
                  render json: serialize_resource(result.value)
                else
                  render_service_error(result.error, code: ERROR_CODES[:validation_error])
                end
              end

              private

              def find_editable_order!
                order = current_user.orders.for_store(current_store).find_by_prefix_id!(params[:order_id])

                # 仅未支付订单可改收货地址（已支付/已退款订单冻结地址）
                unless !order.paid? && order.amount_due.to_f > 0
                  render_error(
                    code: 'order_not_editable',
                    message: I18n.t('pallastrade.api.order_not_editable', default: 'Order cannot be edited'),
                    status: :unprocessable_entity
                  )
                  return nil
                end

                order
              end

              def permitted_params
                params.permit(
                  :shipping_address_id,
                  shipping_address: [
                    :id, :first_name, :last_name,
                    :address1, :address2,
                    :city, :postal_code, :phone, :company,
                    :country_iso, :state_abbr, :state_name
                  ]
                )
              end

              def serialize_resource(resource)
                PallasTrade.api.order_serializer.new(resource, params: serializer_params).to_h
              end
            end
          end
        end
      end
    end
  end
end
