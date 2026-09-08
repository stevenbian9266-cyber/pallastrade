module PallasTrade
  module Api
    module V3
      module Admin
        # REV-P6-8f（FR-R68F-103）：组合级取消编排端点。
        #
        # POST /api/v3/admin/payment_combinations/:id/cancel
        # body（均可选）：
        #   member_ids:      ["order_…", …]  组合成员子集（缺省 = 全部未取消成员）
        #   reason/note/restock_items/refund_payments/notify_customer → 逐成员透传 Orders::Cancel
        #
        # 语义：组合必须 succeeded（pre-payment cancel 仍是 PaymentCombination#cancel 职责）；
        # 每个成员经 Orders::Cancel split-aware durable 退款（组合 Payment + 冻结 split），
        # 资金异步 ExecuteJob。响应为编排聚合（{data:{…}}，不暴露原始整型 PK）。
        class PaymentCombinationsController < BaseController
          before_action :set_combination

          # POST /api/v3/admin/payment_combinations/:id/cancel
          def cancel
            authorize!(:cancel, @combination)

            cast = ->(key) { params.key?(key) ? ActiveModel::Type::Boolean.new.cast(params[key]) : nil }
            result = PallasTrade::Orders::CombinationCancel.call(
              combination: @combination,
              canceler: try_pallastrade_current_user,
              member_ids: decode_member_ids(params[:member_ids]),
              reason: params[:reason],
              note: params[:note],
              restock_items: cast.call(:restock_items),
              refund_payments: cast.call(:refund_payments),
              notify_customer: cast.call(:notify_customer)
            )

            if result.success?
              render json: serialize_cancel_result(result.value)
            else
              render_validation_error(@combination.errors.presence || result.error)
            end
          end

          private

          def set_combination
            @combination = PallasTrade::PaymentCombination
                           .where(store_id: current_store.id)
                           .find_by_prefix_id!(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'Not found', status: :not_found)
          end

          # prefixed order ids → 原始 id 数组；缺省 nil（编排器=全部成员）
          def decode_member_ids(raw)
            return nil if raw.blank?

            Array(raw).filter_map do |prefixed|
              PallasTrade::PrefixedId.decode_prefixed_id(prefixed) if prefixed.is_a?(String)
            end
          end

          def serialize_cancel_result(value)
            members = value.fetch(:members)
            {
              data: {
                id: @combination.prefixed_id,
                type: 'payment_combination',
                attributes: {
                  status: @combination.status,
                  members: members,
                  canceled: value.fetch(:canceled).map { |m| member_attrs(m) },
                  skipped: value.fetch(:skipped).map { |m| member_attrs(m, :reason) },
                  failed: value.fetch(:failed).map { |m| member_attrs(m, :error) }
                }
              }
            }
          end

          def member_attrs(member, extra_key = nil)
            attrs = { order_id: member.fetch(:order_prefixed_id), order_number: member.fetch(:order_number) }
            attrs[extra_key] = member[extra_key] if extra_key
            attrs
          end
        end
      end
    end
  end
end
