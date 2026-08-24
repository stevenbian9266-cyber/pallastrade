# frozen_string_literal: true

# PALLAS-CUSTOM: 售后父子单化（PRD-20260824 FR-033~036）
#
#   GET  /api/v3/admin/orders/:order_id/return_authorizations
#     售后归属视图（FR-036）：返回该订单 + 其子订单的 ReturnAuthorization（父单汇总）
#   POST /api/v3/admin/orders/:order_id/return_authorizations
#     对单个订单/子订单发起售后（FR-033/034），body:
#     { return_authorization_reason_id:, stock_location_id:, memo:, return_items_attributes: [...] }
#   POST /api/v3/admin/orders/:order_id/return_authorizations/bulk_from_parent
#     对整个父订单（含全部子订单）发起售后（FR-035），body:
#     { return_authorization_reason_id:, stock_location_id:, memo: }
module PallasTrade
  module Api
    module V3
      module Admin
        module Orders
          class ReturnAuthorizationsController < BaseController
            scoped_resource :return_authorizations

            # GET /api/v3/admin/orders/:order_id/return_authorizations
            def index
              @collection = scope.order(created_at: :desc)
              render json: { data: serialize_collection(@collection), meta: { count: @collection.size } }
            end

            # POST /api/v3/admin/orders/:order_id/return_authorizations
            def create
              with_order_lock do
                @resource = @parent.return_authorizations.build(
                  reason: find_reason!,
                  stock_location: find_stock_location!,
                  memo: params[:memo],
                  return_items_attributes: ra_items_params
                )
                authorize_resource!(@resource, :create)

                if @resource.save
                  render json: serialize_resource(@resource), status: :created
                else
                  render_validation_error(@resource.errors)
                end
              end
            end

            # POST /api/v3/admin/orders/:order_id/return_authorizations/bulk_from_parent
            def bulk_from_parent
              with_order_lock do
                result = PallasTrade::Returns::FromParent.call(
                  order: @parent,
                  reason: find_reason!,
                  stock_location: find_stock_location!,
                  memo: params[:memo]
                )

                if result.success?
                  render json: { data: serialize_collection(result.value), meta: { count: result.value.size } }, status: :created
                else
                  render_service_error(result.error.respond_to?(:value) ? result.error.value : result.error)
                end
              end
            end

            protected

            def model_class
              PallasTrade::ReturnAuthorization
            end

            def serializer_class
              PallasTrade.api.admin_return_authorization_serializer
            end

            # FR-036：售后归属展示 — 该订单 + 其全部子订单的 RA（父单汇总）
            def scope
              order_ids = [@parent.id] + @parent.children.ids
              PallasTrade::ReturnAuthorization.where(order_id: order_ids)
            end

            private

            def find_reason!
              PallasTrade::ReturnAuthorizationReason.accessible_by(current_ability, :show)
                                                     .find_by_prefix_id!(params[:return_authorization_reason_id])
            end

            def find_stock_location!
              PallasTrade::StockLocation.accessible_by(current_ability, :show)
                                        .find_by_prefix_id!(params[:stock_location_id])
            end

            def ra_items_params
              return [] unless params[:return_items_attributes].is_a?(Array)

              params[:return_items_attributes].map do |item|
                item.permit(:inventory_unit_id, :return_quantity, :pre_tax_amount,
                            :preferred_reimbursement_type_id, :exchange_variant_id, :_destroy)
              end
            end
          end
        end
      end
    end
  end
end
