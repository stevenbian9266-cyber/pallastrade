# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-other-p0-3-邮件自动化-弃单恢复
# AC-004：恢复邮件含商品与带 token 的恢复链接
RSpec.describe PallasTrade::AbandonedCartMailer, type: :mailer do
  let!(:store) { create(:store, code: 'abn_mailer_store', url: 'shop.example.com') }
  let!(:variant) { create(:variant) }
  let!(:cart) do
    create(:order, store: store, email: 'buyer@example.com', state: 'cart', locale: 'en', user: nil)
      .tap { |o| create(:line_item, order: o, variant: variant, quantity: 2) }
  end
  let!(:notification) { store.abandoned_cart_notifications.create!(cart: cart, email: cart.email) }

  it 'renders a recovery email with a tokenized checkout link' do
    mail = described_class.recovery_email(notification)

    expect(mail.to).to eq([cart.email])
    expect(mail.subject).to include(store.name)

    body = mail.body.to_s
    expect(body).to include("/en/checkout/#{cart.id}")
    expect(body).to include("token=#{cart.token}")
    expect(body).to include(PallasTrade.t('abandoned_cart_mailer.recovery_email.resume_checkout'))
  end
end
