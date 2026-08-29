module PallasTrade
  module Carts
    # 订单流程标准电商改造 P1（2026-08-30）：批量 upsert 购物车行（pallastrade_cart_items）。
    #
    # 与 legacy `CartLegacy::AddItem`（Order line_items + recalculate 链）不同：
    # - 按 variant 查找已有 CartItem → 更新数量/勾选；否则新建
    # - 支持 selected 勾选标记（本次结算范围）
    # - Cart 不落金额，无需 recalculate（金额在提交订单时由 Order 权威计算）
    #
    # @example
    #   PallasTrade::Carts::UpsertItems.new.call(
    #     cart: cart,
    #     items: [
    #       { variant_id: "variant_k5nR8xLq", quantity: 2, selected: true },
    #       { variant_id: "variant_m3Rp9wXz", quantity: 1, selected: false }
    #     ]
    #   )
    #
    class UpsertItems
      prepend PallasTrade::ServiceModule::Base

      def call(cart:, items:)
        items = Array(items)
        return success(cart) if items.empty?

        store = cart.store || PallasTrade::Current.store

        ApplicationRecord.transaction do
          items.each do |item_params|
            item_params = item_params.to_h.deep_symbolize_keys
            variant = resolve_variant(store, item_params[:variant_id])
            next unless variant

            quantity = (item_params[:quantity] || 1).to_i
            selected = item_params.key?(:selected) ? !!item_params[:selected] : true

            return failure(variant, "#{variant.name} is not available in #{cart.currency}") if variant.amount_in(cart.currency).nil?

            cart_item = cart.cart_items.find_by(variant_id: variant.id)

            if cart_item
              cart_item.quantity = quantity
              cart_item.selected = selected
              cart_item.metadata = cart_item.metadata.merge(item_params[:metadata].to_h) if item_params[:metadata].present?
            else
              cart_item = cart.cart_items.new(
                quantity: quantity,
                selected: selected,
                variant: variant
              )
              cart_item.metadata = item_params[:metadata].to_h if item_params[:metadata].present?
            end

            return failure(cart_item) unless cart_item.save
          end
        end

        cart.touch_last_activity!
        success(cart)
      end

      private

      def resolve_variant(store, variant_id)
        return nil if variant_id.blank?

        variant = store.variants.find_by_param(variant_id)

        raise ActiveRecord::RecordNotFound.new(
          "Variant '#{variant_id}' not found in this store",
          'PallasTrade::Variant',
          'id',
          variant_id
        ) unless variant

        variant
      end
    end
  end
end
