# frozen_string_literal: true

# PRD-REV-P6-8h AC-R68H-05 —— Payments Ops（只读列表 + OrphanPairing 在线配对）
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Payments Ops pages', type: :request do
  let!(:store) { create(:store, code: 'payments_ops_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PaymentsOpsController).
      to receive(:current_store).and_return(store)
  end

  def completed_payment(store:)
    pm = create(:bogus_payment_method, store: store, active: true)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'pay@example.com')
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: 100, currency: 'USD')
    create(:payment, order: order, payment_method: pm, payment_session: session, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  describe 'GET /admin/payments' do
    it 'AC-R68H-05 lists completed PSP payments of the store' do
      sign_in_as_superuser
      payment = completed_payment(store: store)

      get '/admin/payments'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(payment.prefixed_id)
    end

    it 'AC-R68H-05 store isolation: 其他店支付不出现' do
      sign_in_as_superuser
      other = create(:store, code: "pay_other_#{SecureRandom.hex(4)}")
      other_payment = completed_payment(store: other)

      get '/admin/payments'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_payment.prefixed_id)
    end
  end

  describe 'GET /admin/payments/:id' do
    it 'AC-R68H-05 runs read-only OrphanPairing online (no refunds → matched) and shows pairing card' do
      sign_in_as_superuser
      payment = completed_payment(store: store)

      get "/admin/payments/#{payment.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Provider refund pairing')
      expect(response.body).to include('matched')
    end

    it 'AC-R68H-05 无 read 权限 → 不可见' do
      sign_in admin
      role = create(:role, name: "Limited_#{SecureRandom.hex(4)}")
      create(:role_user, user: admin, role: role, resource: store, store: store)
      allow_any_instance_of(PallasTrade::Admin::PaymentsOpsController).
        to receive(:current_store).and_return(store)
      payment = completed_payment(store: store)

      get "/admin/payments/#{payment.prefixed_id}"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(payment.prefixed_id)
    end
  end
end
