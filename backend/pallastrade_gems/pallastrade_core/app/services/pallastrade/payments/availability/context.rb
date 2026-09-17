# frozen_string_literal: true

# PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片1）—— 求值上下文。
#
# 一次求值需要的可观测事实（业务方案 §66.1 首版 4 维度）：
#   market_id   ← order.market_id → PallasTrade::Current.market（x-pallastrade-country 头解析）
#   country_iso ← 收货地址 → 账单地址（ISO2 大写；地址未填 = 未知）
#   zone_ids    ← 地址所属 Zone（国家/州成员）+ 订单市场 tax_zone
#   currency    ← order.currency → PallasTrade::Current.currency
#
# 「未知」语义（写入 REQ §设计要点 3）：include 条件遇未知上下文 → 视为未命中（fail closed）；
# exclude 条件遇未知上下文 → 视为未命中（fail open，排除必须有正证据）。
module PallasTrade
  module Payments
    module Availability
      class Context
        # Zoneable 类型常量（与 ZoneMember 的多态值一致）
        COUNTRY_TYPE = 'PallasTrade::Country'
        STATE_TYPE = 'PallasTrade::State'

        attr_reader :market_id, :country_iso, :zone_ids, :currency, :authentication_required

        def initialize(market_id: nil, country_iso: nil, zone_ids: nil, currency: nil, authentication_required: false)
          @market_id = presence_string(market_id)
          @country_iso = presence_string(country_iso)&.upcase
          @zone_ids = Array(zone_ids).map(&:to_s).uniq
          @currency = presence_string(currency)&.upcase
          # D15 切片3：本单是否要求 3DS/SCA 认证（由 `ThreeDSecure::Required` 判定；缺省 false = 零回归）
          @authentication_required = authentication_required == true
        end

        # @param order [PallasTrade::Order, nil]
        # @return [PallasTrade::Payments::Availability::Context]
        def self.for_order(order)
          new(
            market_id: order&.market_id.presence || PallasTrade::Current.market&.id,
            country_iso: country_iso_for(order),
            zone_ids: zone_ids_for(order),
            currency: order&.currency.presence || PallasTrade::Current.currency,
            # D15 切片3：订单级判定（已验证在订单对象上做请求内记忆化 → 查询数不随入口数增长）
            authentication_required: authentication_required_for(order)
          )
        end

        # 无订单（后台预览/匿名场景）→ 不要求认证（fail safe，零回归）
        def self.authentication_required_for(order)
          return false if order.blank?

          PallasTrade::Payments::ThreeDSecure::Required.for_order(order)[:required] == true
        rescue StandardError
          false
        end

        def self.country_iso_for(order)
          address = order&.ship_address || order&.bill_address
          address&.country_iso
        end

        # 地址所属 Zone（国家/州成员，单查询）+ 订单市场 tax_zone。
        # 不含默认税区（default_tax_zone 常为兜底 Zone，纳入会让 zone 规则误命中）。
        def self.zone_ids_for(order)
          return [] if order.blank?

          ids = []
          address = order.ship_address || order.bill_address
          ids.concat(zone_ids_matching(address)) if address&.country_id.present?

          market_zone_id = order.try(:market)&.tax_zone&.id
          ids << market_zone_id if market_zone_id.present?

          ids.compact.uniq
        end

        def self.zone_ids_matching(address)
          scope = PallasTrade::ZoneMember.where(zoneable_type: COUNTRY_TYPE, zoneable_id: address.country_id)
          if address.state_id.present?
            scope = scope.or(PallasTrade::ZoneMember.where(zoneable_type: STATE_TYPE, zoneable_id: address.state_id))
          end
          scope.distinct.pluck(:zone_id).compact
        end

        def presence_string(value)
          value.presence&.to_s
        end
      end
    end
  end
end
