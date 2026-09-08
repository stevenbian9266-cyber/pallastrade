# frozen_string_literal: true

# PRD-REV-P6-8g AC-R68G-01~05 —— PaymentCombination 只读可视化（Orders → Payment Combinations）
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Payment Combinations pages', type: :request do
  let!(:store) { create(:store, code: 'combo_ops_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:user) { create(:user) }
  let(:reason) { create(:refund_reason) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PaymentCombinationsController).
      to receive(:current_store).and_return(store)
  end

  def member_order(tag)
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'paid', payment_total: 10,
                   currency: store.default_currency, email: "member#{tag}@example.com")
  end

  def build_combo(status: 'succeeded', member_count: 2)
    combo = create(:payment_combination, store: store, customer: user, amount: 20.0, status: status)
    pm = create(:bogus_payment_method, store: store, active: true)
    payment = create(:payment, order: nil, payment_combination: combo, payment_method: pm,
                               amount: 20, state: 'completed', source: nil, skip_source_requirement: true)
    members = member_count.times.map { |i| member_order(i) }
    splits = members.map do |order|
      create(:payment_split, payment_combination: combo, order: order, payment: payment,
                             authorized_amount: 10, captured_amount: 10, refunded_amount: 0)
    end
    [combo, payment, members, splits]
  end

  describe 'GET /admin/payment_combinations' do
    it 'AC-R68G-01/05 renders store combos with status / amount / member count / refunded total' do
      sign_in_as_superuser
      combo, _payment, _members, splits = build_combo
      # 一笔 split 部分退款 → 同步投影 split.refunded_amount（真实场景由 Refund succeeded 投影写入）
      create(:refund, payment: combo.payments.first, payment_split: splits.first,
                      target_order: splits.first.order, reason: reason, amount: 5,
                      state: 'succeeded', transaction_id: 're_x', succeeded_at: Time.current)
      splits.first.update_columns(refunded_amount: 5.0)

      get '/admin/payment_combinations'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(combo.prefixed_id)
      expect(response.body).to include('succeeded')
      expect(response.body).to include('20.0')
      expect(response.body).to include('5.00') # refunded total
    end

    it 'AC-R68G-01 store isolation: 其他店组合不出现' do
      sign_in_as_superuser
      other = create(:store, code: "combo_other_#{SecureRandom.hex(4)}")
      other_combo = create(:payment_combination, store: other, amount: 10.0, status: 'succeeded')

      get '/admin/payment_combinations'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_combo.prefixed_id)
    end
  end

  describe 'GET /admin/payment_combinations/:id' do
    it 'AC-R68G-02/03 shows member splits (captured/refunded/credit), split refund rows with real state, transaction card' do
      sign_in_as_superuser
      combo, payment, members, splits = build_combo
      txn = PallasTrade::CommerceTransaction.create!(
        store: store, purpose: 'purchase', currency: store.default_currency.to_s,
        amount: 20, payment_combination: combo
      )
      refund = create(:refund, payment: payment, payment_split: splits.first, target_order: members.first,
                               reason: reason, amount: 5, state: 'ambiguous', transaction_id: nil,
                               requested_at: Time.current)
      splits.first.update_columns(refunded_amount: 5.0) # 同步投影（真实由 Refund succeeded 写入）

      get "/admin/payment_combinations/#{combo.prefixed_id}"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(combo.prefixed_id)
      expect(body).to include(members.first.number)
      expect(body).to include('10.00') # captured
      expect(body).to include('5.00') # refunded / credit
      expect(body).to include(refund.prefixed_id)
      expect(body).to include('Ambiguous') # 真实 durable state 徽章（非旧启发式）
      expect(body).to include(txn.prefixed_id) # transaction 互链
    end

    it 'AC-R68G-04 无 read 权限 → 不可见（受限角色被拒）' do
      sign_in admin
      role = create(:role, name: "Limited_#{SecureRandom.hex(4)}")
      create(:role_user, user: admin, role: role, resource: store, store: store)
      allow_any_instance_of(PallasTrade::Admin::PaymentCombinationsController).
        to receive(:current_store).and_return(store)
      combo, = build_combo

      get "/admin/payment_combinations/#{combo.prefixed_id}"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(combo.prefixed_id)
    end
  end
end
