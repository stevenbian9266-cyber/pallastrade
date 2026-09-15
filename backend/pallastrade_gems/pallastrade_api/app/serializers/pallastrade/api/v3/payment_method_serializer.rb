module PallasTrade
  module Api
    module V3
      class PaymentMethodSerializer < BaseSerializer
        typelize name: :string, description: [:string, nullable: true], type: :string,
                 session_required: :boolean, source_required: :boolean,
                 kind: :string, frontend_kind: :string

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
      end
    end
  end
end
