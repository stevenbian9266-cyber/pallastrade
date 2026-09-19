# frozen_string_literal: true

# PALLAS-CUSTOM (2026-09-19, PRD-20260919-shipping-checkout-quote-preview):
# 结算页「只读预览报价」——默认选中配送方式、给出运费/税费估算，**不建单、不写库**。
#
# 设计要点（PRD §3/§9）：
#   1. 金额来自 `Carts::Submit` 的 dry-run（**同一条金额管线**），不做第二套计算；
#   2. 前台表单态地址（可能还没落库）通过 `preview_address` 在内存里覆盖，不写购物车；
#   3. 无地址时用调用方给的 header 国家构造**国家级临时地址**——这是因为
#      `ShippingMethod#include?(nil)` 恒为 false（非数字配送），没有地址就没有费率；
#   4. 方法集合 = 「按国家过滤后的展示集合」与「管线实际算出的费率」求并集：
#      没有费率的项返回 `reason: address_required`（缺州/邮编时可见但不可计价），
#      而不是把它藏掉或显示 0。
module PallasTrade
  module Carts
    class PreviewQuote
      prepend PallasTrade::ServiceModule::Base

      # @param cart [PallasTrade::ShoppingCart]
      # @param shipping_method_id [String, Integer, nil] 前台已选（未落库也可）
      # @param shipping_address [Hash, nil] 表单态地址（iso/state_abbr/city/zipcode...）
      # @param country [String, nil] header 国家（无地址时的临时地址来源）
      def call(cart:, shipping_method_id: nil, shipping_address: nil, country: nil)
        provisional = provisional_address(cart, shipping_address, country)

        result = PallasTrade::Carts::Submit.call(
          cart: cart,
          dry_run: true,
          preview_address: provisional,
          preview_shipping_method_id: shipping_method_id
        )
        unless result.success?
          # 「当前地址下暂不可配送」（例如店铺只有州级 zone，而访客还没填州）
          # 不是预览失败，而是**必须照实回传的预览结果**：金额未知（nil）→ 前台回落
          # 「提交时计算」，同时方法列表带着 `address_required` 告诉用户补完地址就能看到。
          return degraded_payload(cart, provisional, shipping_address, result.value) if unshippable?(result.value)

          return failure(result.value, result.error&.to_s || 'Preview failed')
        end

        payload = result.value
        methods = methods_payload(cart, payload, provisional)

        success(
          payload.merge(
            'estimated' => true,
            'provisional_country' => provisional&.country_iso,
            'address_complete' => shipping_address.present?,
            'methods' => methods,
            'selected_method_id' => selected_method_id(methods, payload['selected_method_id'])
          )
        )
      end

      private

      # 金额未知的降级预览：只有方法集合与原因，金额一律 nil（绝不编 0）。
      def degraded_payload(cart, provisional, shipping_address, order)
        methods = methods_payload(cart, {}, provisional)

        success(
          {
            'cart_id' => cart.prefixed_id,
            'currency' => cart.currency,
            'delivery_total' => nil,
            'display_delivery_total' => nil,
            'tax_total' => nil,
            'display_tax_total' => nil,
            'discount_total' => nil,
            'display_discount_total' => nil,
            'gift_card_total' => nil,
            'display_gift_card_total' => nil,
            'store_credit_total' => nil,
            'display_store_credit_total' => nil,
            'amount_due' => nil,
            'display_amount_due' => nil,
            'total' => nil,
            'display_total' => nil,
            'estimated' => true,
            'provisional_country' => provisional&.country_iso,
            'address_complete' => shipping_address.present?,
            'methods' => methods,
            'selected_method_id' => selected_method_id(methods, nil),
            'delivery_rates' => [],
            'unavailable_reason' => unavailable_reason(order)
          }
        )
      end

      # 订单 warnings 是结构化信号（不靠错误文案匹配）：`delivery_unavailable`
      # 由 `Order#ensure_available_shipping_rates` 写入。
      def unshippable?(value)
        return false unless value.is_a?(PallasTrade::Order)

        Array(value.warnings).any? { |warning| warning[:code].to_s == 'delivery_unavailable' }
      end

      def unavailable_reason(order)
        Array(order.warnings).first&.dig(:code).presence || 'delivery_unavailable'
      end

      # 表单态地址 → 内存 Address（不落库）；缺地址时退化为国家级临时地址。
      def provisional_address(cart, shipping_address, country)
        attrs = normalize_address_params(shipping_address)
        iso = attrs[:country_iso].presence || country.presence
        if iso.blank?
          # 车上有地址（已落库）时直接用快照；否则没有地址也没有国家 → 无法估算运费
          return cart.shipping_address if cart.shipping_address.present?

          return nil
        end

        resolved_country = PallasTrade::Country.find_by(iso: iso.to_s.upcase)
        return cart.shipping_address if resolved_country.blank? && cart.shipping_address.present?

        state = resolved_country&.states&.find_by('LOWER(abbr) = ?', attrs[:state_abbr].to_s.downcase) if attrs[:state_abbr].present?

        PallasTrade::Address.new(
          firstname: attrs[:first_name],
          lastname: attrs[:last_name],
          address1: attrs[:address1],
          address2: attrs[:address2],
          city: attrs[:city],
          zipcode: attrs[:postal_code],
          phone: attrs[:phone],
          country: resolved_country,
          state: state,
          # 见 Address#pricing_only：地址可能只有国家/州，不参与完备性校验，
          # 只为 zone/税区 匹配服务（不落库，事务回滚）。
          pricing_only: true
        )
      end

      def normalize_address_params(params)
        return {} if params.blank?

        source = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        source = source.with_indifferent_access
        {
          first_name: source[:first_name] || source[:firstname],
          last_name: source[:last_name] || source[:lastname],
          address1: source[:address1],
          address2: source[:address2],
          city: source[:city],
          postal_code: source[:postal_code] || source[:zipcode],
          phone: source[:phone],
          country_iso: source[:country_iso] || source[:country],
          state_abbr: source[:state_abbr] || source[:state] || source[:state_name]
        }
      end

      # 展示集合（按国家过滤，与前台列表同源）∪ 管线费率；缺费率者带 reason。
      def methods_payload(cart, payload, provisional)
        display_methods = PallasTrade::Shipping::Estimate.scoped_methods(cart.store, provisional&.country_iso)
        rates_by_method = (payload['delivery_rates'] || []).index_by { |rate| rate['shipping_method_id'] }

        display_methods.map do |method|
          rate = rates_by_method[method.id]
          {
            'id' => method.prefixed_id,
            'raw_id' => method.id,
            'name' => method.name,
            'cost' => rate && rate['cost'],
            'display_cost' => rate ? display_cost(rate['cost'], cart.currency) : nil,
            'reason' => rate ? nil : no_rate_reason(method, cart.currency),
            'selected' => rate ? rate['selected'] : false
          }
        end
      end

      # 无费率的原因：货币不匹配属「不可用」，否则视为「待补地址」（缺州/邮编）。
      def no_rate_reason(method, currency)
        calculator_currency = method.calculator&.preferences&.[](:currency)
        return 'currency_mismatch' if calculator_currency.present? && calculator_currency != currency

        'address_required'
      end

      def display_cost(cost, currency)
        return nil if cost.blank?

        PallasTrade::Money.new(cost.to_d, currency: currency).to_s
      end

      # 默认选中：管线指定的方式（费率成本升序第一）→ 可计价中最便宜的一个。
      def selected_method_id(methods, pipeline_selected_raw_id)
        return nil if methods.empty?

        if pipeline_selected_raw_id.present?
          matched = methods.find { |m| m['raw_id'].to_s == pipeline_selected_raw_id.to_s }
          return matched['id'] if matched
        end

        priced = methods.select { |m| m['cost'].present? }
        return methods.first['id'] if priced.empty?

        priced.min_by { |m| m['cost'].to_d }['id']
      end
    end
  end
end
