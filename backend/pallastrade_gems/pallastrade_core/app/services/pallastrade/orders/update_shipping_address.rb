module PallasTrade
  module Orders
    # 订单模块（PRD-20260829-checkout 收货信息独立填写）：
    # 更新已下单未支付订单的收货地址（shipping_address）。
    #
    # 复用 Carts::Update 的地址赋值模式：
    #   - 优先 shipping_address_id（引用用户已存地址，IDOR-safe：仅限当前用户自己的地址）
    #   - 否则就地更新/新建挂载地址（country_iso / state_abbr 由 Address 模型解析）
    # 已下单订单不重置 checkout 状态机；同步已有 shipment 的 address_id（与 Admin 侧一致）。
    class UpdateShippingAddress
      prepend PallasTrade::ServiceModule::Base

      def call(order:, params:)
        @order = order
        @params = params.to_h.deep_symbolize_keys

        ApplicationRecord.transaction do
          assign_address
          order.save!
          sync_shipments
        end

        success(order.reload)
      rescue ActiveRecord::RecordInvalid => e
        failure(order, e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        failure(order, e.message)
      end

      private

      attr_reader :order, :params

      def assign_address
        address_id_param = params[:shipping_address_id]
        address_params = params[:shipping_address]

        if address_id_param.present?
          address_id = resolve_address_id(address_id_param)
          order.shipping_address_id = address_id if address_id
          return
        end

        return unless address_params.is_a?(Hash)

        if address_params[:id].present?
          address_id = resolve_address_id(address_params[:id])
          order.shipping_address_id = address_id if address_id
        else
          address = order.shipping_address || PallasTrade::Address.new
          address.assign_attributes(address_params.slice(
            :first_name, :last_name, :address1, :address2,
            :city, :postal_code, :phone, :company,
            :country_iso, :state_abbr, :state_name
          ))
          address.user = order.user if order.user
          address.save!
          order.shipping_address = address
        end
      end

      # 已下单订单：同步已有 shipment 的 address_id（与 Admin ShippingAddressController 一致）
      def sync_shipments
        return unless order.shipping_address

        order.shipments.update_all(
          address_id: order.shipping_address.id,
          updated_at: Time.current
        )
      end

      # 解析 prefixed 地址 id → 仅当前订单用户自己的地址（防 IDOR）
      def resolve_address_id(prefixed_id)
        return unless order.user

        decoded = PallasTrade::Address.decode_prefixed_id(prefixed_id)
        decoded ? order.user.addresses.find_by(id: decoded)&.id : nil
      end
    end
  end
end
