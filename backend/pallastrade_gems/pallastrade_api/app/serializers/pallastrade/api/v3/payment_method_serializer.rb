module PallasTrade
  module Api
    module V3
      class PaymentMethodSerializer < BaseSerializer
        typelize name: :string, description: [:string, nullable: true], type: :string,
                 session_required: :boolean, source_required: :boolean,
                 kind: :string, frontend_kind: :string,
                 option_id: :string, method_key: :string, display_name: :string,
                 group: :string, position: :number,
                 entries: 'Array<{ option_id: string, method_key: string, display_name: string, ' \
                          'frontend_kind: string, group: string, position: number }>',
                 client_config: '{ provider: string, environment: string | null, ' \
                                 'publishable: Record<string, string>, session_token: string | null }'

        attributes :name, :description

        attribute :type do |payment_method|
          payment_method.class.api_type
        end

        # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915 切片2）—— 对外暴露「默认入口」身份与前端形态，
        # 让前台可先按 method（kind）维度建列表。additive：未选项化的 provider 返回默认入口值
        # （kind = api_type，frontend_kind = inline/manual），既有字段语义不变。
        attribute :kind do |payment_method|
          payment_method.default_option_kind
        end

        attribute :frontend_kind do |payment_method|
          payment_method.default_option_frontend_kind
        end

        attribute :session_required do |payment_method|
          payment_method.session_required?
        end

        # PALLAS-CUSTOM: D16 切片1（PRD-20260916-payments-d16-payment-method-presentation）--
        # 入口级展示元数据（业务方案 §76.1）：前台支付方法行用 `display_name` 渲染，
        # `option_id` 作行键、`method_key` 作入口维度。additive（既有字段语义不变）。
        attribute :option_id do |payment_method|
          payment_method.option_identifier
        end

        # PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express；§76.1）——
        # 入口分组与顺序（前台支付区按组渲染、按 position 排序）。
        attribute :group do |payment_method|
          payment_method.option_group
        end

        attribute :position do |payment_method|
          payment_method.effective_payment_option['position'].to_i
        end

        # PALLAS-CUSTOM: D7 补口（2026-09-18）—— **入口级列表**也要下发到 cart / order 通道：
        # 购物车单页结账（`cart.payment_methods`）与抽屉都读这条通道，之前只下发了
        # provider 级单入口 → 前台只能显示一行（Apple Pay / Google Pay 看不见）。
        # ⚠️ 本通道**没有订单上下文**，因此入口列表是「已配置且启用」的集合（不过滤）——
        # 真正的可用性判定仍在 `PaymentSessions::Start`（带订单上下文，D8/D11/D15c 同源），
        # 被拒 → 422 `payment_option_not_available` → 前台刷新列表 + 提示重选（既有约定）。
        attribute :entries do |payment_method|
          payment_method.payment_option_entries
        end

        attribute :method_key do |payment_method|
          payment_method.effective_payment_option['kind'] || payment_method.default_option_kind
        end

        attribute :display_name do |payment_method|
          payment_method.option_display_name
        end

        attribute :source_required do |payment_method|
          payment_method.source_required?
        end

        # PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片1）——
        # 前台密钥下发：cart / order / checkout 三条通道同源下发 **publishable 级**凭据，
        # 前端「先读 API、回落 NEXT_PUBLIC_*」（业务方案 §68.4/§76.1）。
        # 唯一组装点 PallasTrade::PaymentMethods::ClientConfig（secret 永不下发）。
        attribute :client_config do |payment_method|
          PallasTrade::PaymentMethods::ClientConfig.call(payment_method)
        end
      end
    end
  end
end
