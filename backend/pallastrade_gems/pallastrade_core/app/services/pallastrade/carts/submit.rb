# frozen_string_literal: true

# PALLAS-CUSTOM: Make Cart submission replay-safe and preserve unselected items (PRD-20260830 checkout v0.2).

module PallasTrade
  module Carts
    # 订单流程标准电商改造 P1（2026-08-30）：提交订单（提交节点）。
    #
    # 语义（标准电商）：购物车 → 提交订单 → 创建正式 Order（state=pending 待支付）
    # + Cart → converted。此后购物车不可再改，支付在 Checkout（纯支付页）完成。
    #
    # 职责：
    #   1. 校验：Cart active、至少 1 个勾选项、变体有价格、库存（LineItem 校验）
    #   2. 快照：line_items（勾选 cart_items）、ship/bill address（复制）、shipments（物流）
    #   3. 权威金额：价格/税/运费/总额走既有 Order 管线（Pricing + TaxRate + OrderUpdater）
    #   4. Cart.convert! + 发布 order.submitted 事件
    #
    # 库存锁定时机（P8）：本服务不落 reservation——按 `stock_reservation_strategy`，
    # :order 策略在 cart 操作阶段锁（后续接入），:payment 策略在支付确认后
    # （Carts::Complete）真正锁定。LineItem 的 AvailabilityValidator 保证提交时有货。
    class Submit
      prepend PallasTrade::ServiceModule::Base

      def call(cart:)
        created = false
        order = cart.with_lock do
          cart.reload

          # A request replay can arrive after the first request converted the Cart.
          # Return the source Order instead of turning a successful checkout into an
          # error. The Cart row lock serializes concurrent submit requests.
          unless cart.active?
            existing_order = cart.orders.order(:id).first
            return success(existing_order) if cart.converted? && existing_order.present?

            return failure(cart, 'Cart is not active')
          end

          # 游客下单必须提供邮箱（Order 对 email 有必填校验）；登录用户取 user.email
          return failure(cart, 'Email is required to place an order') if cart.user.nil? && cart.email.blank?

          selected_items = cart.cart_items.selected.includes(:variant).to_a
          return failure(cart, PallasTrade.t(:there_are_no_items_for_this_order)) if selected_items.empty?

          selected_items.each do |item|
            return failure(item, "#{item.variant.name} is not available in #{cart.currency}") if item.unit_price.nil?
          end

          order = build_order!(cart, selected_items)
          return failure(order, order.errors.full_messages.to_sentence) if order.errors.any?

          successor_cart = create_or_restore_successor_cart!(cart)
          if successor_cart.present?
            order.metadata = order.metadata.merge('successor_cart_id' => successor_cart.prefixed_id)
            order.save!
          end

          cart.convert!
          created = true
          order
        end

        # Publish only after the Cart/Order transaction committed. Event consumers
        # are side effects and must never hide a successfully persisted order.
        publish_submitted_event(order) if created
        success(order)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record, e.record.errors.full_messages.to_sentence)
      end

      private

      def build_order!(cart, selected_items)
        order = cart.store.orders.new(
          user: cart.user,
          email: cart.email.presence || cart.user&.email,
          currency: cart.currency,
          locale: cart.locale,
          cart: cart,
          # 游客会话凭证延续：把 cart token 复制到订单，使同一 cookie/token
          # 可访问结算中的订单（checkout 页/我的订单）。has_secure_token 仅在
          # blank 时生成，因此显式赋值生效。
          token: cart.token,
          state: 'pending',
          status: 'placed',
          submitted_at: Time.current
        )

        # 商品快照（LineItem 锁价/税，独立于 CartItem 实时价）
        selected_items.each do |cart_item|
          order.line_items.new(
            quantity: cart_item.quantity,
            variant: cart_item.variant,
            options: { currency: cart.currency }
          )
        end

        # 地址快照（dup 复制属性；country/state 为 FK 列随复制）——订单不可变
        order.ship_address = cart.shipping_address.dup if cart.shipping_address.present?
        order.bill_address = cart.billing_address.dup if cart.billing_address.present?

        order.save!

        build_fulfillment!(order, cart)
        return order if order.errors.any? || !order.persisted?

        order.update_line_item_prices!
        order.create_tax_charge!
        order.update_with_updater!
        order.save!

        order
      end

      # 复用既有履约管线：分配库存单元 → 生成 shipments + 运费 → 选中与购物车一致的
      # shipping method → 落运费金额。
      def build_fulfillment!(order, cart)
        order.create_proposed_shipments
        # ensure_available_shipping_rates 是状态机私有回调（before_transition），
        # 标准流程不走 next 状态机，因此 send 显式调用。
        order.send(:ensure_available_shipping_rates)
        return if order.errors.any?

        select_shipping_rates!(order, cart)
        order.set_shipments_cost
      end

      def select_shipping_rates!(order, cart)
        order.shipments.each do |shipment|
          rate = if cart.shipping_method_id.present?
                   shipment.shipping_rates.find { |r| r.shipping_method_id == cart.shipping_method_id }
                 else
                   shipment.shipping_rates.first
                 end

          shipment.selected_shipping_rate_id = rate.id if rate
        end
      end

      # Normal partial checkout gets a new active Cart containing only the
      # unselected rows. Buy Now restores the previously active Cart recorded by
      # the storefront and never mixes its one-off Cart into the regular cart.
      def create_or_restore_successor_cart!(cart)
        metadata = cart.metadata.with_indifferent_access
        if metadata[:checkout_source] == 'buy_now'
          previous_cart_id = metadata[:previous_cart_id]
          return if previous_cart_id.blank?

          return cart.store.shopping_carts.active.find_by_prefix_id(previous_cart_id)
        end

        unselected_items = cart.cart_items.where(selected: false).to_a
        return if unselected_items.empty?

        successor = cart.store.shopping_carts.create!(
          user: cart.user,
          email: cart.email,
          customer_note: cart.customer_note,
          currency: cart.currency,
          locale: cart.locale,
          shipping_address: cart.shipping_address,
          billing_address: cart.billing_address,
          shipping_method: cart.shipping_method,
          metadata: metadata.except(:checkout_source, :previous_cart_id, :successor_cart_id).merge(
            predecessor_cart_id: cart.prefixed_id
          )
        )

        unselected_items.each { |item| item.update!(cart: successor) }
        successor
      end

      def publish_submitted_event(order)
        order.publish_event('order.submitted', payload: { order_id: order.prefixed_id })
      rescue StandardError => e
        Rails.logger.error(
          "order.submitted publication failed order_id=#{order.prefixed_id} " \
          "error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end
