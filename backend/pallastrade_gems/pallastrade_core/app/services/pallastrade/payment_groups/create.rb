# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Creates a PallasTrade::PaymentGroup from a set of unpaid order ids.
# All money math is server-side; the client only supplies order ids.
module PallasTrade
  module PaymentGroups
    class Create
      prepend PallasTrade::ServiceModule::Base

      # @param store [PallasTrade::Store] the current store
      # @param order_ids [Array<String,Integer>] prefixed or raw ids of member orders
      # @param user [User, nil] current customer (combined payment is for logged-in users)
      # @return [ServiceResult<PallasTrade::PaymentGroup>]
      def call(store:, order_ids:, user: nil)
        ApplicationRecord.transaction do
          orders = resolve_orders(store, order_ids)
          return failure(nil, :orders_not_found) if orders.size != order_ids.size || orders.empty?

          error = validate_orders!(orders, user)
          return failure(nil, error) if error

          group = PallasTrade::PaymentGroup.new(
            store: store,
            customer: user,
            currency: orders.first.currency,
            status: 'pending'
          )
          group.orders = orders
          group.amount = group.total_minus_store_credits

          if group.save
            success(group)
          else
            failure(group)
          end
        end
      end

      private

      def resolve_orders(store, order_ids)
        ids = order_ids.map { |id| resolve_id(store, id) }.compact
        return [] if ids.empty?

        store.orders.where(id: ids.uniq).to_a
      end

      def resolve_id(store, id)
        order = store.orders.find_by_prefix_id(id.to_s)
        order ? order.id : (id.to_s.match?(/\A\d+\z/) ? id.to_i : nil)
      end

      # Returns an error symbol, or nil when valid.
      def validate_orders!(orders, user)
        return :mixed_currency if orders.map(&:currency).uniq.size > 1
        return :orders_not_owned if user.present? && orders.any? { |o| o.user_id.present? && o.user_id != user.id }
        return :order_canceled if orders.any?(&:canceled?)
        return :order_already_paid if orders.any? { |o| o.outstanding_balance <= 0 }
        return :order_in_active_group if orders.any? { |o| o.payment_group&.active? }

        nil
      end
    end
  end
end
