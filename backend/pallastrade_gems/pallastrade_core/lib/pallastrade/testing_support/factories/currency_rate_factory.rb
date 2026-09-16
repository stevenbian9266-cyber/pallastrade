# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot）——
# 汇率工厂：默认一条「手工、无生效窗口」的 USD/CNY 汇率。
FactoryBot.define do
  factory :currency_rate, class: 'PallasTrade::CurrencyRate' do
    base_currency { 'USD' }
    quote_currency { 'CNY' }
    rate { BigDecimal('7.1') }
    source { 'manual' }
    priority { 10 }
    status { 'active' }
    identity_key do
      PallasTrade::CurrencyRate.identity_key_for(
        base_currency: base_currency, quote_currency: quote_currency, source: source,
        effective_from: effective_from, store: store
      )
    end
    metadata { {} }
  end
end
