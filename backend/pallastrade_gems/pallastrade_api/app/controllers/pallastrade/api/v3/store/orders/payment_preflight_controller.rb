# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        module Orders
          # PRD-20260919-checkout：补付重验只读端点
          #   GET /api/v3/store/orders/:order_id/payment_preflight
          #
          # 返回 `OrderCheckout::Revalidate`（dry_run: true）报告：失效商品、金额变化、
          # 硬阻断原因、重验后报价（金额/版本/窗口）。**零副作用**——不落库、不发事件、
          # 不建支付会话（dry-run 在订单锁事务内执行后回滚）。
          #
          # 与写路径同源：`Transactions::Start` 复用同一服务（dry_run: false），
          # 因此「页面显示金额 == 实际扣款金额」由同一份实现保证。
          # 访问控制复用 OrderResolvable（customer/token + store isolation）。
          class PaymentPreflightController < Store::BaseController
            include PallasTrade::Api::V3::OrderResolvable

            before_action :find_order, only: :show

            # GET /api/v3/store/orders/:order_id/payment_preflight
            def show
              result = PallasTrade::OrderCheckout::Revalidate.call(order: @order)
              return render_service_error(result.error, code: :validation_error) unless result.success?

              render json: serializer_class.new(result.value, params: serializer_params).to_h
            end

            private

            def serializer_class
              PallasTrade::Api::V3::Store::Orders::PaymentPreflightSerializer
            end
          end
        end
      end
    end
  end
end
