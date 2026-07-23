module PallasTradeAdyen
  module Webhooks
    module Actions
      class CreateSource
        SOURCE_KLASS_MAP = {
          affirm: PallasTradeAdyen::PaymentSources::Affirm,
          alipay: PallasTradeAdyen::PaymentSources::Alipay,
          bacs: PallasTradeAdyen::PaymentSources::Bacs,
          bankTransfer_IBAN: PallasTradeAdyen::PaymentSources::BankTransfer,
          klarna_b2b: PallasTradeAdyen::PaymentSources::Billie,
          blik: PallasTradeAdyen::PaymentSources::Blik,
          clearpay: PallasTradeAdyen::PaymentSources::Clearpay,
          eps: PallasTradeAdyen::PaymentSources::Eps,
          ideal: PallasTradeAdyen::PaymentSources::Ideal,
          facilypay_3x: PallasTradeAdyen::PaymentSources::Oney,
          facilypay_4x: PallasTradeAdyen::PaymentSources::Oney,
          facilypay_6x: PallasTradeAdyen::PaymentSources::Oney,
          facilypay_10x: PallasTradeAdyen::PaymentSources::Oney,
          facilypay_12x: PallasTradeAdyen::PaymentSources::Oney,
          scalapay_3x: PallasTradeAdyen::PaymentSources::Scalapay,
          klarna: PallasTradeAdyen::PaymentSources::Klarna,
          klarna_account: PallasTradeAdyen::PaymentSources::Klarna,
          klarna_paynow: PallasTradeAdyen::PaymentSources::Klarna,
          klarna_paylater: PallasTradeAdyen::PaymentSources::Klarna,
          klarna_payovertime: PallasTradeAdyen::PaymentSources::Klarna,
          onlineBanking_CZ: PallasTradeAdyen::PaymentSources::OnlineBankingCzechRepublic,
          onlineBanking_PL: PallasTradeAdyen::PaymentSources::OnlineBankingPoland,
          paybybank: PallasTradeAdyen::PaymentSources::PayByBank,
          paypal: PallasTradeAdyen::PaymentSources::Paypal,
          paypo: PallasTradeAdyen::PaymentSources::Paypo,
          paysafecard: PallasTradeAdyen::PaymentSources::Paysafecard,
          ratepay_directdebit: PallasTradeAdyen::PaymentSources::RatePayDirectDebit,
          riverty: PallasTradeAdyen::PaymentSources::Riverty,
          samsungpay: PallasTradeAdyen::PaymentSources::SamsungPay,
          sepadirectdebit: PallasTradeAdyen::PaymentSources::SepaDirectDebit,
          trustly: PallasTradeAdyen::PaymentSources::Trustly,
          wechatpaySDK: PallasTradeAdyen::PaymentSources::WechatPay,
          wechatpayQR: PallasTradeAdyen::PaymentSources::WechatPay,
          ach: PallasTradeAdyen::PaymentSources::AchDirectDebit,
          afterpaytouch: PallasTradeAdyen::PaymentSources::Afterpay,
          afterpaytouch_US: PallasTradeAdyen::PaymentSources::CashAppAfterpay,
          alipay_hk: PallasTradeAdyen::PaymentSources::AlipayHk,
          alma: PallasTradeAdyen::PaymentSources::Alma,
          ancv: PallasTradeAdyen::PaymentSources::Ancv,
          atome: PallasTradeAdyen::PaymentSources::Atome,
          benefit: PallasTradeAdyen::PaymentSources::Benefit,
          bcmc: PallasTradeAdyen::PaymentSources::Bancontact,
          bcmc_mobile: PallasTradeAdyen::PaymentSources::Bancontact,
          bizum: PallasTradeAdyen::PaymentSources::Bizum,
          boleto: PallasTradeAdyen::PaymentSources::Boleto,
          cashapp: PallasTradeAdyen::PaymentSources::Cashapp,
          doku_alfamart: PallasTradeAdyen::PaymentSources::Doku,
          doku_indomaret: PallasTradeAdyen::PaymentSources::Doku,
          dana: PallasTradeAdyen::PaymentSources::Dana,
          duitnow: PallasTradeAdyen::PaymentSources::Duitnow,
          fastlane: PallasTradeAdyen::PaymentSources::Fastlane,
          molpay_ebanking_fpx_MY: PallasTradeAdyen::PaymentSources::Fpx,
          gcash: PallasTradeAdyen::PaymentSources::Gcash,
          givex: PallasTradeAdyen::PaymentSources::GiftCards,
          genericgiftcard: PallasTradeAdyen::PaymentSources::GiftCards,
          valuelink: PallasTradeAdyen::PaymentSources::GiftCards,
          svs: PallasTradeAdyen::PaymentSources::GiftCards,
          giropay: PallasTradeAdyen::PaymentSources::Giropay,
          grabpay_MY: PallasTradeAdyen::PaymentSources::Grabpay,
          grabpay_PH: PallasTradeAdyen::PaymentSources::Grabpay,
          grabpay_SG: PallasTradeAdyen::PaymentSources::Grabpay
        }.freeze

        def initialize(event:, payment_method:, user:)
          @event = event
          @payment_method = payment_method
          @user = user
        end

        def call
          if event.payment_method_reference.in?(PallasTradeAdyen::Config.credit_card_sources)
            find_or_create_credit_card
          else
            find_or_create_source
          end
        end

        def find_or_create_source
          source_klass_factory.find_or_create_by(
            gateway_payment_profile_id: event.stored_payment_method_id.presence || event.psp_reference,
            payment_method: payment_method
          ) do |source|
            source.user = user
          end
        end

        def find_or_create_credit_card
          PallasTradeAdyen::Webhooks::Actions::FindOrCreateCreditCard.new(
            event: event,
            gateway: payment_method,
            user: user
          ).call
        end

        private

        attr_reader :event, :payment_method, :user

        delegate :payment_method_reference, to: :event

        def source_klass_factory
          SOURCE_KLASS_MAP[event.payment_method_reference] || PallasTradeAdyen::PaymentSources::Unknown
        end
      end
    end
  end
end
