module PallasTrade
  module Api
    module V3
      module Store
        # 订单流程标准电商改造 P1（2026-08-30）：订单确认页可选配送方式。
        # GET /api/v3/store/shipping_methods —— 返回前端展示的配送方式（名称/描述含费率标签）。
        # 权威运费在提交订单（Carts::Submit）时按所选方式在 Order 上计算。
        #
        # Catalog F-2（2026-09-16）：新增 `?country=` 可选参数（按 zone 过滤，命中不了则
        # 回退全集，绝不因未建模的国家而声称「不配送」）与时效字段下发。
        class ShippingMethodsController < Store::BaseController
          def index
            methods = PallasTrade::Shipping::Estimate.scoped_methods(current_store, params[:country])
            render json: methods.map { |m| serializer_class.new(m, params: serializer_params).to_h }
          end

          private

          def serializer_class
            PallasTrade.api.delivery_method_serializer
          end
        end
      end
    end
  end
end
