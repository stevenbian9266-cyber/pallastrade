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
        group = nil
        ApplicationRecord.transaction do
          orders = resolve_orders(store, order_ids)
          return failure(nil, :orders_not_found) if orders.size != order_ids.size || orders.empty?

          error = validate_orders!(orders, user)
          return failure(nil, error) if error

          # PALLAS-CUSTOM: 幂等复用（PRD-20260824-checkout-合并支付复用已有支付组继续支付）——
          # 订单已在 active 支付组时不再报错：复用最近创建的组继续支付，未入组的订单一并并入。
          existing = active_group_for(orders)
          if existing
            return failure(nil, :mixed_currency) if orders.any? { |o| o.currency != existing.currency }

            group = merge_orders_into(existing, orders)
          else
            group = PallasTrade::PaymentGroup.new(
              store: store,
              customer: user,
              currency: orders.first.currency,
              status: 'pending'
            )
            group.orders = orders
            group.amount = group.total_minus_store_credits

            # 保存失败（例如成员订单校验不通过）时回滚整个事务，
            # 避免留下半成品的 payment group 脏数据（PALLAS-CUSTOM 2026-08-24）。
            raise ActiveRecord::Rollback unless group.save
          end
        end

        group ? success(group) : failure(group)
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

        nil
      end

      # 订单关联的 active 支付组；多个时复用最近创建的组（created_at 最大）。
      def active_group_for(orders)
        orders
          .filter_map { |o| o.payment_group if o.payment_group&.active? }
          .uniq
          .max_by(&:created_at)
      end

      # 把本次订单（含分散在其它 active 组、或未入组的）并入目标组并重算金额；
      # 因移动而清空的旧组标记 canceled，避免残留 pending 空组。
      def merge_orders_into(target, orders)
        old_groups = orders
                     .filter_map { |o| o.payment_group if o.payment_group&.active? && o.payment_group_id != target.id }
                     .uniq

        orders.each do |order|
          order.update!(payment_group_id: target.id) if order.payment_group_id != target.id
        end

        old_groups.each do |old|
          old.reload
          next unless old.orders.empty? && old.active?

          old.cancel!
        rescue StateMachines::InvalidTransition
          nil
        end

        target.reload
        target.amount = target.total_minus_store_credits
        raise ActiveRecord::Rollback unless target.save

        target
      end
    end
  end
end
