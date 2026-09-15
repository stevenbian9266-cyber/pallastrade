module PallasTrade
  module Api
    module V3
      class PaymentMethodSerializer < BaseSerializer
        typelize name: :string, description: [:string, nullable: true], type: :string,
                 session_required: :boolean, source_required: :boolean,
                 kind: :string, frontend_kind: :string,
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
