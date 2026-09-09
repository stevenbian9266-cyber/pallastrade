module PallasTrade
  module Api
    module V3
      module Admin
        # REV-P6-8l（FR-R68L-104；8h Payments Ops 数据面 API 化）
        # 顶层支付只读（组合 Payment order_id=nil 亦可达——无法经 orders/:id/payments 嵌套访问）：
        #   GET /api/v3/admin/payments/:id                     → { data: PaymentSerializer }
        #   GET /api/v3/admin/payments/:id/orphan_pairing      → 在线只读 OrphanPairing（8d/8h 语义）
        #
        # orphan_pairing 只读不变式（8d）：零本地写 / 零 provider mutation / 绝不自动退款；
        # provider 异常 / 无能力 / 无 session 锚点 → 降级 status（unsupported/unavailable）不 500。
        class PaymentsController < BaseController
          before_action :set_payment, only: [:show, :orphan_pairing]

          def show
            authorize!(:read, @payment)
            render json: serialize_resource(@payment)
          end

          def orphan_pairing
            authorize!(:read, @payment)
            result = PallasTrade::Refunds::OrphanPairing.call(payment: @payment)

            if result.success?
              render json: pairing_data(result.value)
            else
              # 理论上 call 只对 nil payment failure；防御性降级。
              render json: pairing_data(
                PallasTrade::Refunds::OrphanPairingResult.new(
                  status: 'unavailable',
                  reasons: ['ORPHAN_PAIRING_UNAVAILABLE']
                )
              )
            end
          end

          private

          def serializer_class
            PallasTrade.api.admin_payment_serializer
          end

          def set_payment
            @payment = store_payments_scope.find_by_prefix_id!(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'Not found', status: :not_found)
          end

          # Payment 无 store_id 列（belongs_to order / payment_combination，均 optional）——
          # store 作用域经锚点派生：组合支付（combo.store_id）∪ 订单支付（order.store_id）。
          # 游离 legacy payment（无锚点）不在顶层可达（8h Rails Admin 亦在 order 上下文）。
          def store_payments_scope
            combo_payments = PallasTrade::Payment.where(
              payment_combination_id: PallasTrade::PaymentCombination.where(store_id: current_store.id).select(:id)
            )
            order_payments = PallasTrade::Payment.where(
              order_id: PallasTrade::Order.where(store_id: current_store.id).select(:id)
            )
            combo_payments.or(order_payments)
          end

          def pairing_data(value)
            {
              status: value.status,
              reasons: value.reasons,
              provider_refund_references: value.provider_refund_references,
              matched: value.matched,
              orphans: value.orphans,
              local_unmatched: value.local_unmatched,
              observed_at: value.observed_at&.iso8601
            }
          end
        end
      end
    end
  end
end
