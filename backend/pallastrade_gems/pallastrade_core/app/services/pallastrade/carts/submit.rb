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

      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-shipping-checkout-quote-preview):
      # `dry_run: true` = **只读预览报价**：走完全相同的一条金额管线（行价 → 税 → 运费 → 抵扣），
      # 但在事务内捕获纯数据快照后 `ActiveRecord::Rollback`，绝不推进任何状态：
      #   - 不 `cart.convert!`（购物车仍 active）
      #   - 不建 successor cart
      #   - **不发布 `order.submitted`**（该发布在事务外，回滚撤不掉，必须显式跳过）
      # `preview_address` / `preview_shipping_method_id` 用于「地址还没落库」的场景
      # （前台表单态）：在内存里覆盖订单快照地址与选中配送方式，不写购物车。
      def call(cart:, dry_run: false, preview_address: nil, preview_shipping_method_id: nil)
        created = false
        preview = nil
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

          order = build_order!(
            cart, selected_items,
            preview_address: preview_address,
            preview_shipping_method_id: preview_shipping_method_id
          )
          return failure(order, order.errors.full_messages.to_sentence) if order.errors.any?

          if dry_run
            preview = preview_payload(order, cart)
            raise ActiveRecord::Rollback
          end

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
        # dry-run（预览）不落库、不推进状态 → 绝不发布事件。
        if dry_run
          return success(preview) if preview.present?

          return failure(cart, 'Preview could not be computed')
        end

        publish_submitted_event(order) if created
        success(order)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record, e.record.errors.full_messages.to_sentence)
      end

      private

      def build_order!(cart, selected_items, preview_address: nil, preview_shipping_method_id: nil)
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
        # PALLAS-CUSTOM (2026-09-13, PRD-20260913-checkout-billing-mode FR-004):
        # 账单快照优先级 = 显式账单地址 → 否则配送地址副本（兜底）。修复
        # 「前端勾选同配送（use_shipping）但订单 bill_address 为空」的缺陷。
        billing_source = cart.billing_address || cart.shipping_address
        order.bill_address = billing_source.dup if billing_source.present?

        # PALLAS-CUSTOM (2026-09-19, PRD-20260919-shipping-checkout-quote-preview):
        # 预览模式下用「表单态地址」（可能是国家级临时地址）覆盖快照，**不写购物车**。
        if preview_address.present?
          order.ship_address = preview_address
          order.bill_address = preview_address if order.bill_address.blank?
        end

        order.save!

        build_fulfillment!(order, cart, preview_shipping_method_id: preview_shipping_method_id)
        return order if order.errors.any? || !order.persisted?

        order.update_line_item_prices!
        order.create_tax_charge!
        # PALLAS-CUSTOM (2026-09-14, PRD-20260914-checkout-cart-discount-codes-canonical FR-004):
        # 购物车上的优惠码「意图」在此兑现（与 Orders::Create#apply_coupon 同源）；
        # 不可用 → 抛错回滚（绝不静默按原价下单）。
        apply_discount_code!(order, cart)
        # PALLAS-CUSTOM (2026-09-14, 修复 GATE-2026-09-14T12-44-52): 先让金额管线跑完（行价 + 税 + 运费 →
        # order.total 落库），再兑现礼品卡。否则 GiftCards::Apply 的
        # amount = min(remaining, order.total) 会读到尚未计算的 total（dev E2E 实测为 0）
        # → store credit 金额 0 → 校验报「Amount must be greater than 0」且提交失败。
        order.update_with_updater!
        # PALLAS-CUSTOM (2026-09-14, PRD-20260914-checkout-cart-gift-cards-canonical FR-004):
        # 购物车上的礼品卡码在提交时兑现（车阶段只承载意图，金额副作用落在 Order）。
        apply_gift_card!(order, cart)
        # PALLAS-CUSTOM (2026-09-14, PRD-20260914-checkout-cart-store-credits-canonical FR-004):
        # 店铺余额意图同在金额管线之后兑现（与礼品卡同序；意图层已互斥，不会同时存在）。
        apply_store_credit!(order, cart)
        # 兑现后重建 payment_total / amount_due / payment_state（store-credit payment 已入账）。
        order.update_with_updater!
        order.save!

        order
      end

      # FR-004：把购物车上的礼品卡码交给权威套用路径（order.apply_gift_card）。
      # 车阶段不建 payment；这里才真正创建 store-credit payment 并占用余额。
      # 不可用 → 抛错回滚（绝不静默按原价下单）。
      def apply_gift_card!(order, cart)
        code = (cart.private_metadata || {})[PallasTrade::Carts::ApplyGiftCard::METADATA_KEY].presence
        return if code.blank?

        # 复用与端点同一套校验（存在/未过期/未核销），保证错误口径一致
        validation = PallasTrade::Carts::ApplyGiftCard.validate_code(cart.store, code)
        if validation
          order.errors.add(:base, validation)
          raise ActiveRecord::RecordInvalid, order
        end

        gift_card = cart.store.gift_cards.find_by(code: code)
        # 零额订单（全额折扣 / 免费商品 + 免运费）无款可付：不建 0 额 store credit（StoreCredit
        # 校验 amount > 0），也不占用礼品卡余额。校验已在此前完成，故非法码仍然会失败。
        return if order.total.zero?

        result = order.apply_gift_card(gift_card)
        return if result.success?

        order.errors.add(:base, result.value.to_s.presence || PallasTrade::Carts::ApplyGiftCard::NOT_FOUND)
        raise ActiveRecord::RecordInvalid, order
      end

      # FR-004：把购物车上的店铺余额意图交给权威套用路径（Checkout::AddStoreCredit）。
      # 金额 = min(意图金额, 最终 outstanding_balance)；零额订单无款可付 → 跳过。
      def apply_store_credit!(order, cart)
        amount = PallasTrade::Carts::ApplyStoreCredit.requested_amount(cart)
        return if amount.nil? || amount.zero? || order.total.zero?

        # 与 GiftCards::Apply 同口径：店铺缺 store-credit 支付方式时补建 —— 否则
        # Checkout::AddStoreCredit `raise 'Store credit payment method could not be found'`
        # （不是 service failure）→ 提交变成 500。
        ensure_store_credit_payment_method!(cart.store)

        result = begin
          PallasTrade.checkout_add_store_credit_service.call(order: order, amount: amount)
        rescue StandardError => e
          # 权威服务在异常路径上直接 raise → 收敛为「提交失败、不落单」，不让金额意图静默丢失。
          Rails.error.report(e, context: { order_id: order.id, cart_id: cart.id }, source: 'PallasTrade.carts.submit')
          nil
        end

        if result.nil?
          fail_submission!(order, PallasTrade.t(:store_credit_not_available))
        elsif !result.success?
          message = result.value.is_a?(String) ? result.value : PallasTrade.t(:error_user_does_not_have_any_store_credits)
          fail_submission!(order, message)
        end
      end

      def fail_submission!(order, message)
        order.errors.add(:base, message)
        raise ActiveRecord::RecordInvalid, order
      end

      # 与 PallasTrade::GiftCards::Apply#ensure_store_credit_payment_method! 同口径，
      # 但修正了一个真实缺陷：既有记录可能是**停用**状态（dev 实测 active=false）→
      # Checkout::AddStoreCredit 的 `available` 作用域取不到 → raise；
      # 因此只要状态有变更就必须落库，不能只在新建时 save。
      def ensure_store_credit_payment_method!(store)
        payment_method = store.payment_methods.find_or_initialize_by(
          type: 'PallasTrade::PaymentMethod::StoreCredit'
        )
        payment_method.name ||= PallasTrade.t(:store_credit_name)
        payment_method.active = true
        payment_method.save! if payment_method.new_record? || payment_method.changed?
        payment_method
      end

      # FR-004：把购物车上的优惠码交给权威套用路径（PromotionHandler::Coupon）。
      # 应用码不消耗码（占用/核销由 PromotionRedemption reserve/commit 负责）。
      def apply_discount_code!(order, cart)
        code = (cart.private_metadata || {})[PallasTrade::Carts::ApplyDiscountCode::METADATA_KEY].presence
        return if code.blank?

        order.coupon_code = code
        handler = PallasTrade::PromotionHandler::Coupon.new(order).apply
        return if handler.successful?

        order.errors.add(:base, handler.error.to_s.presence || PallasTrade::Carts::ApplyDiscountCode::NOT_FOUND)
        raise ActiveRecord::RecordInvalid, order
      end

      # 复用既有履约管线：分配库存单元 → 生成 shipments + 运费 → 选中与购物车一致的
      # shipping method → 落运费金额。
      def build_fulfillment!(order, cart, preview_shipping_method_id: nil)
        order.create_proposed_shipments
        # ensure_available_shipping_rates 是状态机私有回调（before_transition），
        # 标准流程不走 next 状态机，因此 send 显式调用。
        order.send(:ensure_available_shipping_rates)
        return if order.errors.any?

        select_shipping_rates!(order, cart, preview_shipping_method_id: preview_shipping_method_id)
        order.set_shipments_cost
      end

      def select_shipping_rates!(order, cart, preview_shipping_method_id: nil)
        # PALLAS-CUSTOM (2026-09-19, PRD-20260919-shipping-checkout-quote-preview):
        # 预览可显式指定配送方式（前台还没落库的选择）；其次用购物车上的选择，最后取管道默认（最便宜）。
        desired_method_id = preview_shipping_method_id.presence || cart.shipping_method_id
        order.shipments.each do |shipment|
          rate = if desired_method_id.present?
                   shipment.shipping_rates.find { |r| r.shipping_method_id.to_s == desired_method_id.to_s }
                 else
                   shipment.shipping_rates.detect(&:selected) || shipment.shipping_rates.first
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

      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-shipping-checkout-quote-preview):
      # 预览快照：在事务内把金额与方法费率拍成**纯数据**（回滚后 AR 属性会被
      # Rails 还原，不能依赖对象状态）；display_* 一律用 Order 自身的展示方法，
      # 与 order_serializer（prepare 的权威报价）同源。
      def preview_payload(order, cart)
        {
          'cart_id' => cart.prefixed_id,
          'currency' => order.currency,
          'delivery_total' => order.delivery_total.to_s,
          'display_delivery_total' => order.display_delivery_total.to_s,
          'tax_total' => order.tax_total.to_s,
          'display_tax_total' => order.display_tax_total.to_s,
          'discount_total' => order.discount_total.to_s,
          'display_discount_total' => order.display_discount_total.to_s,
          'gift_card_total' => order.gift_card_total.to_s,
          'display_gift_card_total' => order.display_gift_card_total.to_s,
          'store_credit_total' => order.total_applied_store_credit.to_s,
          'display_store_credit_total' => order.display_total_applied_store_credit.to_s,
          'amount_due' => order.combined_amount_due.to_s,
          'display_amount_due' => order.display_combined_amount_due.to_s,
          'total' => order.combined_total.to_s,
          'display_total' => order.display_combined_total.to_s,
          'selected_method_id' => order.shipments.filter_map { |s| s.selected_shipping_rate&.shipping_method_id }.first,
          'delivery_rates' => order.shipments.flat_map do |shipment|
            shipment.shipping_rates.map do |rate|
              {
                'shipping_method_id' => rate.shipping_method_id,
                'cost' => rate.cost.to_s,
                'selected' => rate.id == shipment.selected_shipping_rate_id
              }
            end
          end
        }
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
