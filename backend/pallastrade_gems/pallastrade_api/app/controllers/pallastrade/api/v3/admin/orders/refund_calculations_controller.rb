# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4b-refund-allocation (FR-003/FR-004, PR-P6-3)
#
# 只读「退款计算预览」：GET /api/v3/admin/orders/:order_id/refund_calculation
#
#   * 原金额   = line_item.amount（折前）
#   * 分摊优惠 = `Promotions::Allocation::AdjustmentAllocation`（促销维度，含 basis 明细）
#   * 可退金额 = `ReturnItem` 权威计算（`Calculator::Returns::DefaultRefundAmount`，REV-P6-3 冻结）
#
# 可选 query：`quantities[<line_item prefixed id>]=n`（缺省 = 每行全量退）。
# 纯只读：不创建 Refund/ReturnItem、不改订单、不跑 Promotion Engine。
# 授权沿用 `Orders::BaseController`：父订单经 `current_store.orders` 解析 + `authorize_parent!`
# （read 动作只要求订单的 :show 权限；JWT 管理员由 CanCanCan 判定，API key 走 scope 校验）。
module PallasTrade
  module Api
    module V3
      module Admin
        module Orders
          class RefundCalculationsController < BaseController
            # 本端点渲染「从订单派生的只读投影」，不加载 orders 资源本身
            # （否则 ResourceController 会按关联名查找 @parent.refund_calculations）。
            skip_before_action :set_resource, only: [:show]

            # GET /api/v3/admin/orders/:order_id/refund_calculation
            def show
              quantities = parsed_quantities
              return if performed?

              preview = PallasTrade::Promotions::Allocation::RefundPreview.call(
                order: @parent,
                quantities: quantities
              )

              render json: { data: serializer_class.new(preview).to_h }
            end

            private

            def serializer_class
              PallasTrade.api.admin_refund_calculation_serializer
            end

            # 逐项校验：非整型 / 未知行 / 超量 → 422（不进入服务层，避免静默降级）。
            def parsed_quantities
              raw = raw_quantities
              return {} if raw.blank?

              quantities = {}
              error = nil

              raw.to_h.each do |key, value|
                if value.to_s !~ /\A\d+\z/
                  error = "quantity must be a non-negative integer for line_item_id: #{key}"
                  break
                end

                line_item = line_items_by_prefixed_id[key.to_s]
                if line_item.nil?
                  error = "unknown line_item_id: #{key}"
                  break
                end

                requested = value.to_i
                if requested > line_item.quantity
                  error = "quantity out of range for line_item_id: #{key}"
                  break
                end

                quantities[line_item.id] = requested
              end

              return quantities if error.nil?

              render_error(code: :validation_error, message: error, status: 422)
              {}
            end

            # 动态 key（`li_…`）→ 必须绕过 strong params 过滤（否则 ActionController 抛 400）。
            def raw_quantities
              raw = params[:quantities]
              return nil if raw.blank?
              return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)

              raw
            end

            def line_items_by_prefixed_id
              @line_items_by_prefixed_id ||= @parent.line_items.index_by(&:prefixed_id)
            end
          end
        end
      end
    end
  end
end
