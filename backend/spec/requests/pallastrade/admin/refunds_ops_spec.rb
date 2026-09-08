# frozen_string_literal: true

# PRD-REV-P6-8a AC-R68A-03~09 —— Refund Ops（Orders → Refunds）列表/详情（只读）+ order 内嵌退款 state 徽章
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Refunds Ops pages', type: :request do
  let!(:store) { create(:store, code: 'refunds_ops_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:reason) { create(:refund_reason) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::RefundsOpsController).
      to receive(:current_store).and_return(store)
  end

  def order_in(store, number: nil)
    create(:order, store: store, number: number, state: 'pending', status: 'placed',
                   item_total: 1000, total: 1000, payment_state: 'balance_due')
  end

  def completed_payment(order:)
    pm = create(:bogus_payment_method, store: order.store, active: true)
    payment = create(:payment, order: order, payment_method: pm, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  def make_refund(order:, state: 'succeeded', amount: 10, transaction_id: 're_bogus', **overrides)
    create(:refund, payment: completed_payment(order: order), reason: reason,
                    amount: amount, state: state, transaction_id: transaction_id, **overrides)
  end

  describe 'GET /admin/refunds' do
    it 'AC-R68A-03 renders current store refunds with state badge / amount / order link' do
      sign_in_as_superuser
      order = order_in(store, number: 'R-REF-8A')
      refund = make_refund(order: order, transaction_id: 're_abc', succeeded_at: Time.current)

      get '/admin/refunds'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(refund.prefixed_id)
      expect(response.body).to include('Succeeded')
      expect(response.body).to include(order.number)
      expect(response.body).to include('re_abc')
    end

    it 'AC-R68A-03/04 store isolation + default sort created_at desc' do
      sign_in_as_superuser
      other_store = create(:store, code: "ref_other_#{SecureRandom.hex(4)}")
      other_refund = make_refund(order: order_in(other_store), transaction_id: 're_other')

      older = make_refund(order: order_in(store), amount: 10, created_at: 2.days.ago)
      newer = make_refund(order: order_in(store), amount: 11, created_at: 1.day.ago)

      get '/admin/refunds'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_refund.prefixed_id)
      expect(response.body.index(newer.prefixed_id)).to be < response.body.index(older.prefixed_id)
    end

    it 'AC-R68A-04 supports state ransack filter' do
      sign_in_as_superuser
      amb = make_refund(order: order_in(store), state: 'ambiguous', transaction_id: nil)
      ok_ref = make_refund(order: order_in(store), state: 'succeeded', transaction_id: 're_ok')

      get '/admin/refunds', params: { q: { state_in: ['ambiguous'] } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(amb.prefixed_id)
      expect(response.body).not_to include(ok_ref.prefixed_id)
    end
  end

  describe 'GET /admin/refunds/:id' do
    it 'AC-R68A-05 renders §63 fields (state/provider ref/idempotency/timestamps/payment/order)' do
      sign_in_as_superuser
      order = order_in(store)
      payment = completed_payment(order: order)
      refund = create(:refund, payment: payment, reason: reason, amount: 30,
                               state: 'succeeded', transaction_id: 're_prov_8a',
                               provider_idempotency_key: 'refund:re_xyz:execute',
                               succeeded_at: Time.current)

      get "/admin/refunds/#{refund.prefixed_id}"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(refund.prefixed_id)
      expect(body).to include('re_prov_8a')
      expect(body).to include('refund:re_xyz:execute')
      expect(body).to include('Requested at')
      expect(body).to include('Succeeded at')
      expect(body).to include(payment.prefixed_id)
      expect(body).to include(order.number)
      expect(body).to include('Recovery')
    end

    it 'AC-R68A-06 renders read-only reconciliation card for a bogus succeeded refund' do
      sign_in_as_superuser
      refund = make_refund(order: order_in(store), transaction_id: 're_bogus_8a', succeeded_at: Time.current)

      get "/admin/refunds/#{refund.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Reconciliation (read-only)')
    end

    it 'AC-R68A-07 renders restock placeholder when refund has no linked customer return' do
      sign_in_as_superuser
      refund = make_refund(order: order_in(store))

      get "/admin/refunds/#{refund.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('no linked customer return')
    end

    it 'AC-R68A-09 rejects non-privileged access (no manage Refund)' do
      sign_in admin
      limited_role = create(:role, name: "limited_#{SecureRandom.hex(4)}")
      create(:role_user, user: admin, role: limited_role, resource: store, store: store)
      refund = make_refund(order: order_in(store))

      # 非超管、无 manage/read Refund → 无法进入（BaseController#authorize_admin → authorize! :admin/:show）
      get "/admin/refunds/#{refund.prefixed_id}"

      expect(response.status).to be_in([302, 403])
    end
  end

  describe 'order show refunds inline table (legacy convergence)' do
    it 'AC-R68A-08 renders real refund.state badge instead of transaction_id heuristic' do
      sign_in_as_superuser
      order = order_in(store, number: 'R-INLINE-8A')
      refund = make_refund(order: order, amount: 5, transaction_id: 're_inline', succeeded_at: Time.current)

      get "/admin/orders/#{order.prefixed_id}"

      expect(response).to have_http_status(:ok)
      # 内嵌退款表现在展示真实 state（succeeded → Succeeded badge），而非旧 pending/completed 启发式
      expect(response.body).to include('Succeeded')
      expect(response.body).to include(refund.prefixed_id)
    end
  end
end
