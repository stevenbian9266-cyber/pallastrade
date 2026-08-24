# PALLAS-CUSTOM: 多订单拆分（PRD-20260823 + PRD-20260824 增强）
#
# Splits an order into multiple new orders by partitioning its line items.
# Used by:
#   - admin manual split (POST /api/v3/admin/orders/:id/split)
#   - checkout-time auto split (by warehouse) — see Checkout::SplitOrders
#   - payment-success auto split（支付后系统拆单，allow_paid: true）
#
# The source order keeps the line items that were not assigned to any group.
# New orders inherit store/user/channel/currency/addresses, set parent/split_from
# (父子单结构), and start in `cart` state so the normal checkout pipeline rebuilds.
# 已支付订单拆分时按行项目继承已付状态（资金分摊，避免重复支付）。
module PallasTrade
  module Orders
    class Splitter
      # 拆单业务错误（如跨店铺目标缺商品）——事务回滚并转为 failure
      class SplitterError < StandardError; end

      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] the source order
      # @param groups [Hash<Symbol/String, Array<String,Integer>>, nil] group key → line item ids
      #   （nil 时用 by: 策略自动分组）
      # @param by [Symbol, nil] 分组策略 :warehouse | :store | :custom（groups 为空时使用）
      # @param allow_paid [Boolean] 是否允许拆分已支付订单（支付后系统拆单）
      # @return [ServiceResult<Array<PallasTrade::Order>>]
      def call(order:, groups: nil, by: nil, allow_paid: false)
        ApplicationRecord.transaction do
          return failure(order, { code: :order_not_splittable, message: PallasTrade.t(:order_not_splittable) }) unless splittable?(order, allow_paid: allow_paid)

          groups ||= resolve_groups(order, by)

          return failure(order, { code: :no_split_groups, message: PallasTrade.t(:no_split_groups) }) if groups.blank?

          paid = order.paid?
          new_orders = groups.filter_map do |_key, spec|
            ids, options = normalize_group(spec)
            build_split_order(order, Array(ids), store_id: options[:store_id],
                                                stock_location_id: options[:stock_location_id],
                                                paid: paid)
          end

          return failure(order, { code: :no_split_line_items, message: PallasTrade.t(:no_split_line_items) }) if new_orders.empty?

          # Recalculate source + children totals/shipments
          order.reload
          PallasTrade::OrderUpdater.new(order).update
          new_orders.each do |o|
            PallasTrade::OrderUpdater.new(o).update
            # 资金分摊在 OrderUpdater 重算之后执行（OrderUpdater 会基于 payments 重置 payment_total）
            allocate_payment(o, order) if paid
          end

          success(new_orders)
        end
      rescue SplitterError => e
        failure(order, { code: :split_error, message: e.message })
      end

      private

      # 兼容两种 group 形态：
      #   { "g1" => ["li_x"] }                                        —— 数组（继承源订单店铺）
      #   { "g1" => { "line_item_ids" => [...], "store_id" => "st_x",
      #               "stock_location_id" => "loc_y" } }              —— Hash（跨店/指定仓库，FR-027）
      def normalize_group(spec)
        if spec.is_a?(Hash) && spec.key?('line_item_ids')
          [
            Array(spec['line_item_ids']),
            {
              store_id: spec['store_id'],
              stock_location_id: spec['stock_location_id']
            }
          ]
        else
          [Array(spec), {}]
        end
      end

      def resolve_groups(order, by)
        return {} if by.blank?

        result = PallasTrade::Orders::Splitting::Grouper.call(order: order, by: by)
        result.success? ? result.value : {}
      end

      def splittable?(order, allow_paid: false)
        !order.completed? && !order.canceled? && (allow_paid || order.payments.completed.none?)
      end

      def build_split_order(source, line_item_ids, paid: false, store_id: nil, stock_location_id: nil)
        line_items = source.line_items.where(id: line_item_ids).to_a
        return nil if line_items.empty?

        target_store = resolve_target_store(source, store_id)
        # PALLAS-CUSTOM: 跨店铺拆单（FR-028）— 目标店铺必须有该商品，否则返回明确错误
        if target_store != source.store
          missing = line_items.reject { |li| li.variant&.product && li.variant.product.store_id == target_store.id }
          unless missing.empty?
            raise SplitterError,
                  PallasTrade.t(:order_split_store_missing_product,
                                 default: '商品 %{item} 在目标店铺不可用', item: missing.first.variant&.name || 'N/A')
          end
        end

        split_order = PallasTrade::Order.new(
          store: target_store,
          user: source.user,
          channel: source.channel,
          market: source.market,
          currency: source.currency,
          email: source.email,
          locale: source.locale,
          bill_address: source.bill_address,
          ship_address: source.ship_address,
          split_from: source,
          # PALLAS-CUSTOM: 父子单结构（PRD-20260824）— 拆出的子订单归入同一父订单
          parent: source,
          last_ip_address: source.last_ip_address,
          created_by: source.created_by
        )
        split_order.save!

        # Move the selected line items onto the new order (triggers inventory/adjustment recalc)
        line_items.each { |li| li.update!(order: split_order) }

        split_order
      end

      def resolve_target_store(source, store_id)
        return source.store if store_id.blank?

        PallasTrade::Store.find_by_prefix_id!(store_id)
      end

      # PALLAS-CUSTOM: 资金分摊（FR-021）— 原订单已支付时，为子订单创建真实 Payment 记录
      # （Order#paid? 基于 payments.valid.completed），金额按行项目合计分摊，避免重复支付。
      def allocate_payment(split_order, source)
        amount = split_order.line_items.sum(&:amount)
        return if amount.to_f <= 0

        source_payment = source.payments.completed.first
        split_order.payments.create!(
          amount: amount,
          state: 'completed',
          payment_method: source_payment&.payment_method,
          source: source_payment&.source,
          response_code: source_payment&.response_code
        )
        split_order.update_columns(payment_total: amount, payment_state: 'paid')
      end
    end
  end
end
