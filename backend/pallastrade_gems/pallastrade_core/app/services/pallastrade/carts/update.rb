module PallasTrade
  module Carts
    # 订单流程标准电商改造 P1（2026-08-30）：更新购物车（pallastrade_carts 实体）。
    # 与 legacy `CartLegacy::Update`（Order 同表 + checkout 自动推进 + 库存预留）不同，
    # Cart 无 checkout 状态机：只维护属性/地址/物流方式/商品行。库存与金额在提交订单
    # （Carts::Submit）时在 Order 上统一处理。
    class Update
      prepend PallasTrade::ServiceModule::Base

      # PALLAS-CUSTOM (2026-09-13, PRD-20260913-checkout-billing-mode FR-003):
      # `billing_mode=custom` 但账单地址不完整时阻止半空地址落库（事务回滚）。
      class IncompleteBillingAddress < StandardError; end

      # 账单地址最小完整集（与 Storefront 表单必填项一致）
      BILLING_REQUIRED_FIELDS = %i[first_name last_name address1 city postal_code country_iso].freeze

      def call(cart:, params:)
        @cart = cart
        @params = params.to_h.deep_symbolize_keys

        ApplicationRecord.transaction do
          assign_cart_attributes
          assign_address(:shipping_address)
          # PALLAS-CUSTOM (2026-09-13, FR-001/002): 账单语义先于地址写入解析 ——
          # `same_as_shipping` 清除既有账单地址；`custom` 才消费显式 billing_address*。
          assign_billing_mode
          assign_address(:billing_address)
          assign_shipping_method

          cart.save!

          process_items
        end

        cart.touch_last_activity!
        success(cart)
      rescue ActiveRecord::RecordNotFound
        raise
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        failure(cart, e.message)
      end

      private

      attr_reader :cart, :params

      def assign_cart_attributes
        cart.email = params[:email] if params[:email].present?
        cart.customer_note = params[:customer_note] if params.key?(:customer_note)
        cart.currency = params[:currency].upcase if params[:currency].present?
        cart.locale = params[:locale] if params[:locale].present?
        cart.metadata = cart.metadata.merge(params[:metadata].to_h) if params[:metadata].present?
      end

      def assign_address(address_type)
        # FR-001：`same_as_shipping` 时忽略任何显式账单载荷（语义 = 同配送地址）
        return if address_type == :billing_address && @billing_mode == :same_as_shipping

        address_id_param = params[:"#{address_type}_id"]
        address_params = params[address_type]

        if address_id_param.present?
          address_id = resolve_address_id(address_id_param)
          cart.public_send(:"#{address_type}_id=", address_id) if address_id
          return
        end

        return unless address_params.is_a?(Hash)

        if address_params[:id].present?
          address_id = resolve_address_id(address_params[:id])
          cart.public_send(:"#{address_type}_id=", address_id) if address_id
        else
          validate_billing_address!(address_params) if address_type == :billing_address
          # 购物车暂存收件信息：提交订单时快照锁定到 Order。
          # 复用已挂地址就地更新（避免孤儿地址累积）；与 legacy 不同，Cart 不收件后
          # 重建发货/重置 checkout——那是 Order 的职责。
          address = cart.public_send(address_type) || PallasTrade::Address.new
          address.assign_attributes(address_params.slice(
            :first_name, :last_name, :address1, :address2,
            :city, :postal_code, :phone, :company,
            :country_iso, :state_abbr, :state_name, :quick_checkout
          ))
          address.user = cart.user if cart.user
          address.save!
          cart.public_send(:"#{address_type}=", address)
        end
      end

      # FR-001/FR-002：账单地址语义解析（`billing_mode` 优先，legacy `use_shipping` 兼容）。
      def assign_billing_mode
        @billing_mode = resolve_billing_mode
        # `same_as_shipping` = 语义上「账单地址即配送地址」：清除既有独立账单地址，
        # 提交订单时由 Carts::Submit 回退复制配送地址（FR-004）。
        cart.billing_address = nil if @billing_mode == :same_as_shipping
      end

      def resolve_billing_mode
        raw = params[:billing_mode].presence
        if raw.present?
          return :same_as_shipping if raw.to_s == 'same_as_shipping'
          return :custom if raw.to_s == 'custom'

          # 非法枚举值：忽略（不猜测语义、不落库）
          return nil
        end

        return nil unless params.key?(:use_shipping)

        case params[:use_shipping]
        when true, 'true', '1' then :same_as_shipping
        when false, 'false', '0' then :custom
        end
      end

      # FR-003：`custom` 模式下校验账单地址最小完整集（与既有地址合并后判断，
      # 支持局部更新）；不完整则回滚事务，不得落库半空地址。
      def validate_billing_address!(address_params)
        return unless @billing_mode == :custom

        existing = cart.billing_address&.attributes&.slice(*BILLING_REQUIRED_FIELDS.map(&:to_s)) || {}
        merged = existing.symbolize_keys.merge(address_params.slice(*BILLING_REQUIRED_FIELDS))
        missing = BILLING_REQUIRED_FIELDS.select { |field| merged[field].blank? }
        return if missing.empty?

        raise IncompleteBillingAddress, "Billing address is incomplete (missing: #{missing.join(', ')})"
      end

      def assign_shipping_method
        return if params[:shipping_method_id].blank?

        # PALLAS-CUSTOM (2026-08-30, bugfix): PallasTrade::ShippingMethod 是全局资源
        # （表无 store_id，经 zone 与商店关联），Store 没有 shipping_methods 关联。
        # 与 Store::ShippingMethodsController 一致按前缀全局查找（dm_ 前缀）。
        cart.shipping_method = PallasTrade::ShippingMethod.find_by_prefix_id!(params[:shipping_method_id])
      end

      def process_items
        return unless params[:items].is_a?(Array)

        result = PallasTrade::Carts::UpsertItems.call(
          cart: cart,
          items: params[:items]
        )

        raise StandardError, result.error.to_s if result.failure?
      end

      def resolve_address_id(prefixed_id)
        return unless cart.user

        decoded = PallasTrade::Address.decode_prefixed_id(prefixed_id)
        decoded ? cart.user.addresses.find_by(id: decoded)&.id : nil
      end
    end
  end
end
