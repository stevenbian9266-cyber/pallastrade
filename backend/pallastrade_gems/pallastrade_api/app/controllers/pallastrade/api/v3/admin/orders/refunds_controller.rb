module PallasTrade
  module Api
    module V3
      module Admin
        module Orders
          class RefundsController < BaseController
            scoped_resource :refunds

            # POST /api/v3/admin/orders/:order_id/refunds
            def create
              error_rendered = false

              with_order_lock do
                payment = @parent.payments.accessible_by(current_ability, :update).find_by_prefix_id!(params[:payment_id])
                reason = PallasTrade::RefundReason.accessible_by(current_ability, :show).find_by_prefix_id!(params[:refund_reason_id]) if params[:refund_reason_id].present?
                reason ||= PallasTrade::RefundReason.accessible_by(current_ability, :show).first

                refund = payment.refunds.build(
                  amount: params[:amount],
                  reason: reason,
                  transaction_id: nil
                )
                authorize_resource!(refund, :create)

                # REV-P6-3 (FR-R63-101/102)：组合退款创建即冻结 ownership —— 可选
                # payment_split_id / target_order_id。冻结 split 时 amount 上限由
                # Refund 校验 amount_within_frozen_split_limit（split.captured − refunded）
                # 强制执行（FR-R63-103 / AC-6011）。预检失败立即渲染返回（勿依赖
                # save 前的 errors —— valid? 会清空预加错误）。
                combination = payment.payment_combination
                if params[:payment_split_id].present?
                  split = PallasTrade::PaymentSplit.accessible_by(current_ability, :update).find_by_prefix_id(params[:payment_split_id])
                  if split && split.payment_id == payment.id && split.order_id.present?
                    refund.payment_split = split
                    refund.target_order ||= split.order
                  else
                    refund.errors.add(:payment_split, :invalid)
                    error_rendered = true
                    render_validation_error(refund.errors)
                    next
                  end
                end
                if params[:target_order_id].present?
                  target_order = PallasTrade::Order.accessible_by(current_ability, :update).find_by_prefix_id(params[:target_order_id])
                  in_combination = combination && combination.orders.where(id: target_order&.id).exists?
                  is_single_order = target_order&.id == payment.order_id
                  if in_combination || is_single_order
                    refund.target_order = target_order
                  else
                    refund.errors.add(:target_order, :invalid)
                    error_rendered = true
                    render_validation_error(refund.errors)
                    next
                  end
                end

                unless refund.save
                  error_rendered = true
                  render_validation_error(refund.errors)
                  next
                end

                @resource = refund
                # P0-6 (PRD FR-064): Refund 敏感操作审计。
                PallasTrade::Audit.record(
                  actor: (respond_to?(:current_admin_user) ? current_admin_user : 'admin'),
                  action: 'refund',
                  resource: refund,
                  after: {
                    payment_id: payment.prefixed_id,
                    amount: refund.amount.to_s,
                    reason_id: reason&.prefixed_id,
                    currency: refund.currency,
                    payment_split_id: refund.payment_split&.prefixed_id,
                    target_order_id: refund.target_order&.prefixed_id
                  }
                )
              end
              return if error_rendered

              # REV-P6-2：durable Refund(requested) 已提交 → enqueue ExecuteJob（异步执行；
              # provider I/O 只发生在后台 Job，REV-INV-03）。响应 201 + state=requested；
              # 终态/失败经 GET /orders/:id/refunds 观测（FR-R62-301 / AC-R62-07）。
              PallasTrade::Refunds::ExecuteJob.perform_later(@resource.id)
              render json: serialize_resource(@resource.reload), status: :created
            end

            protected

            def model_class
              PallasTrade::Refund
            end

            def serializer_class
              PallasTrade.api.admin_refund_serializer
            end

            def scope
              PallasTrade::Refund.where(payment_id: @parent.payment_ids)
            end

            def collection_includes
              [:payment, :reason]
            end
          end
        end
      end
    end
  end
end
