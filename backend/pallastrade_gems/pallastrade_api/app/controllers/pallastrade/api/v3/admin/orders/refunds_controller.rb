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

                unless refund.errors.empty?
                  error_rendered = true
                  render_validation_error(refund.errors)
                  next
                end

                # D14 切片1（PRD-20260916-payments-d14-refund-approval）：人工退款走策略门
                # （Refunds::Submit）——超阈值的退款只落 durable(requested) + 待批记录，
                # **不入队执行**；批准后由 Refunds::Approvals::Approve 入队（零资金副作用）。
                # request_key 为可选请求级幂等键（重复提交 → 返回既有退款，不建第二笔）。
                outcome = PallasTrade::Refunds::Submit.call(
                  payment: payment,
                  amount: params[:amount],
                  reason: reason,
                  refunder_id: refund_actor_id,
                  request_key: params[:request_key],
                  reimbursement: refund.reimbursement,
                  payment_split: refund.payment_split,
                  target_order: refund.target_order,
                  actor: audit_actor
                )

                unless outcome.success?
                  error_rendered = true
                  render_validation_error(outcome.value.respond_to?(:errors) ? outcome.value.errors : refund.errors)
                  next
                end

                @resource = outcome.value
                # P0-6 (PRD FR-064): Refund 敏感操作审计。
                PallasTrade::Audit.record(
                  actor: (respond_to?(:current_admin_user) ? current_admin_user : 'admin'),
                  action: 'refund',
                  resource: @resource,
                  after: {
                    payment_id: payment.prefixed_id,
                    amount: @resource.amount.to_s,
                    reason_id: reason&.prefixed_id,
                    currency: @resource.currency,
                    payment_split_id: @resource.payment_split&.prefixed_id,
                    target_order_id: @resource.target_order&.prefixed_id,
                    approval_status: @resource.approval&.status
                  }
                )
              end
              return if error_rendered

              # REV-P6-2 / D14：durable Refund(requested) 已提交 —— 执行入队由 Refunds::Submit
              # 在事务提交后完成（策略未要求审批时）；待批退款保持 submitted，等待第二人。
              render json: serialize_resource(@resource.reload), status: :created
            end

            protected

            def model_class
              PallasTrade::Refund
            end

            # D14 切片1：发起人（admin 用户 id）—— 审批「不能自批」的 SoD 基准。
            def refund_actor_id
              user = respond_to?(:current_admin_user) ? current_admin_user : nil
              user.respond_to?(:id) ? user.id : nil
            end

            # D14 切片1：审计 actor（策略门审计沿用后台统一形态）。
            def audit_actor
              user = respond_to?(:current_admin_user) ? current_admin_user : nil
              if user.respond_to?(:id)
                { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
              else
                'admin'
              end
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
