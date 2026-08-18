# frozen_string_literal: true

require 'rails_helper'

# PRD-20260815-catalog-邮件管理整合 AC-004
RSpec.describe PallasTrade::EmailTemplate, type: :model do
  let(:store) { create(:store, code: 'emtp_model_test') }

  describe 'validations' do
    it 'is valid with a store, key, name and subject' do
      expect(build(:email_template, store: store)).to be_valid
    end

    it 'rejects a duplicate key per store' do
      create(:email_template, store: store, key: 'order.confirm_email')
      expect(build(:email_template, store: store, key: 'order.confirm_email')).to be_invalid
    end

    it 'allows the same key on different stores' do
      other = create(:store, code: 'emtp_model_test_2')
      create(:email_template, store: store, key: 'order.confirm_email')
      expect(build(:email_template, store: other, key: 'order.confirm_email')).to be_valid
    end

    it 'rejects a missing subject' do
      expect(build(:email_template, store: store, subject: nil)).to be_invalid
    end
  end

  describe '#render_subject' do
    it 'substitutes {placeholders}' do
      tpl = build(:email_template, store: store, subject: 'Order {order_number}')
      expect(tpl.render_subject(order_number: 'R1')).to eq('Order R1')
    end

    it 'leaves unknown placeholders untouched' do
      tpl = build(:email_template, store: store, subject: 'Hi {missing}')
      expect(tpl.render_subject({})).to eq('Hi {missing}')
    end
  end

  describe '#render_body' do
    it 'renders html body with placeholder substitution' do
      tpl = build(:email_template, store: store, body_html: '<h1>{customer_name}</h1>')
      expect(tpl.render_body(:html, customer_name: 'Bob')).to eq('<h1>Bob</h1>')
    end

    it 'renders text body' do
      tpl = build(:email_template, store: store, body_text: 'Hi {customer_name}')
      expect(tpl.render_body(:text, customer_name: 'Bob')).to eq('Hi Bob')
    end
  end

  describe '#placeholders_list' do
    it 'splits the comma-separated placeholder string' do
      tpl = build(:email_template, store: store, placeholders: 'order_number, store_name')
      expect(tpl.placeholders_list).to eq(%w[order_number store_name])
    end
  end
end
