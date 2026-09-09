# frozen_string_literal: true

require 'spec_helper'

# PRD-20260909-payments-admin-api-v3-只读端点-payment_combinations-index-show-refunds-sh (REV-P6-8l)
# AC-R68L-01~05：admin v3 只读端点
#   GET  /api/v3/admin/payment_combinations            index（分页/store 隔离/status 过滤）
#   GET  /api/v3/admin/payment_combinations/:id        show（expand members/payments/transaction；404）
#   GET  /api/v3/admin/orders/:oid/refunds/:rid        show（refund 详情；404）
#   GET  /api/v3/admin/payments/:pid                   show（组合 Payment order_id=nil 可达）
#   GET  /api/v3/admin/payments/:pid/orphan_pairing    OrphanPairing 只读（bogus → unsupported 降级；零写）
RSpec.describe '/api/v3/admin payments ops (read-only, REV-P6-8l)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def build_succeeded_combination(amount: 20.0)
    combo = create(:payment_combination, store: store, customer: user, amount: amount, status: 'succeeded')
    create(:payment, order: nil, payment_combination: combo, payment_method: payment_method,
                     amount: amount, state: 'completed', source: nil, skip_source_requirement: true)
    combo
  end

  def add_member(combination, amount, tag)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: amount, total: amount, payment_state: 'paid', payment_total: amount,
                           currency: store.default_currency, email: "readonly#{tag}@example.com")
    create(:payment_split, payment_combination: combination, order: order,
                           payment: combination.payments.first,
                           authorized_amount: amount, captured_amount: amount, refunded_amount: 0)
    order
  end

  describe 'GET /api/v3/admin/payment_combinations (AC-R68L-01)' do
    it '返回本店组合列表（{data[],meta}，含 member_count/refunded_total），跨店不可见' do
      combo = build_succeeded_combination
      m1 = add_member(combo, 10, 'a')
      add_member(combo, 10, 'b')
      other = create(:store, code: "other_#{SecureRandom.hex(4)}")
      foreign_combo = create(:payment_combination, store: other, customer: user, amount: 5, status: 'pending')

      get '/api/v3/admin/payment_combinations', headers: headers

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:data].length).to eq(1)
      combo_json = body[:data].first
      expect(combo_json[:id]).to eq(combo.prefixed_id)
      expect(combo_json[:status]).to eq('succeeded')
      expect(combo_json[:member_count]).to eq(2)
      expect(combo_json[:refunded_total]).to eq('0.0')
      expect(body[:meta][:count]).to eq(1)
      expect(body[:data].map { |d| d[:id] }).not_to include(foreign_combo.prefixed_id)
      expect(combo_json).not_to have_key(:members) # 未 expand 不展开
    end
  end

  describe 'GET /api/v3/admin/payment_combinations/:id (AC-R68L-02)' do
    it 'expand=members,payments,transaction 返回详情；跨店 → 404' do
      combo = build_succeeded_combination
      m1 = add_member(combo, 10, 'a')
      txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'combined_payment',
                                                     currency: store.default_currency, amount: 20,
                                                     payment_combination: combo, state: 'completed')

      get "/api/v3/admin/payment_combinations/#{combo.prefixed_id}?expand=members,payments,transaction",
          headers: headers

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:id]).to eq(combo.prefixed_id)
      expect(body[:status]).to eq('succeeded')
      members = body[:members]
      expect(members.length).to eq(1)
      expect(members.first[:order_id]).to eq(m1.prefixed_id)
      expect(members.first[:captured_amount]).to eq('10.0')
      expect(members.first[:refunded_amount]).to eq('0.0')
      expect(members.first[:credit_allowed]).to eq('10.0')
      expect(body[:payments].first[:id]).to eq(combo.payments.first.prefixed_id)
      expect(body[:transaction][:id]).to eq(txn.prefixed_id)
      # 无整型 PK 泄漏
      expect(json_response.to_s).not_to include("\"#{m1.id}\"")

      other = create(:store, code: "other_#{SecureRandom.hex(4)}")
      foreign = create(:payment_combination, store: other, customer: user, amount: 5, status: 'pending')
      get "/api/v3/admin/payment_combinations/#{foreign.prefixed_id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v3/admin/orders/:oid/refunds/:rid (AC-R68L-03)' do
    let(:order) do
      create(:order, store: store, state: 'complete', completed_at: Time.current,
                     item_total: 100, total: 100, payment_state: 'paid')
    end
    let(:payment) do
      create(:payment, order: order, payment_method: payment_method, amount: 100,
                       state: 'completed', source: nil, skip_source_requirement: true)
    end

    it '返回 refund 详情（顶层属性含 state/amount/reason）；跨店 → 404' do
      reason = create(:refund_reason)
      refund = create(:refund, payment: payment, reason: reason, amount: 60, transaction_id: nil)

      get "/api/v3/admin/orders/#{order.prefixed_id}/refunds/#{refund.prefixed_id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:state]).to eq(refund.reload.state)
      expect(body[:amount]).to be_present
      expect(body[:payment_id]).to eq(payment.prefixed_id)
      expect(body[:refund_reason_id]).to eq(reason.prefixed_id)

      other = create(:store, code: "other_#{SecureRandom.hex(4)}")
      other_pm = create(:bogus_payment_method, store: other, active: true)
      other_order = create(:order, store: other, state: 'complete', completed_at: Time.current,
                                   item_total: 10, total: 10, payment_state: 'paid')
      other_payment = create(:payment, order: other_order, payment_method: other_pm, amount: 10,
                                       state: 'completed', source: nil, skip_source_requirement: true)
      other_refund = create(:refund, payment: other_payment, reason: reason, amount: 5, transaction_id: nil)
      get "/api/v3/admin/orders/#{other_order.prefixed_id}/refunds/#{other_refund.prefixed_id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v3/admin/payments/:id + orphan_pairing (AC-R68L-04/05)' do
    it '组合 Payment（order_id=nil）经顶层可达 show；bogus orphan_pairing → unsupported 降级不 500 且零写' do
      combo = build_succeeded_combination
      add_member(combo, 10, 'a')
      payment = combo.payments.first
      expect(payment.order_id).to be_nil

      get "/api/v3/admin/payments/#{payment.prefixed_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(payment.prefixed_id)

      refund_count = PallasTrade::Refund.count
      get "/api/v3/admin/payments/#{payment.prefixed_id}/orphan_pairing", headers: headers
      expect(response).to have_http_status(:ok)
      data = json_response
      expect(%w[matched needs_attention not_applicable unsupported unavailable]).to include(data[:status])
      # 组合 legacy payment 无 provider session 锚点 → unavailable(UNLINKED_LEGACY_PAYMENT) 降级不 500
      expect(data[:status]).to eq('unavailable')
      expect(data).to have_key(:orphans)
      expect(data).to have_key(:reasons)
      expect(PallasTrade::Refund.count).to eq(refund_count) # 零写
    end

    it '跨店 payment → 404（show + orphan_pairing）' do
      other = create(:store, code: "other_#{SecureRandom.hex(4)}")
      other_combo = create(:payment_combination, store: other, customer: user, amount: 5, status: 'succeeded')
      other_payment = create(:payment, order: nil, payment_combination: other_combo,
                                       payment_method: payment_method, amount: 5, state: 'completed',
                                       source: nil, skip_source_requirement: true)
      get "/api/v3/admin/payments/#{other_payment.prefixed_id}", headers: headers
      expect(response).to have_http_status(:not_found)
      get "/api/v3/admin/payments/#{other_payment.prefixed_id}/orphan_pairing", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
