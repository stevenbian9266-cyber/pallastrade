# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B2) AC-006 / AC-010
# —— 列表页运营报表卡：指标渲染、异常降级（页面恒 200）、零写。
RSpec.describe 'Admin Disputes Ops report (DSP-P7-10 B2)', type: :request do
  let!(:store) { create(:store, code: "p710_rep_ops_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).to receive(:current_store).and_return(store)
  end

  def make_dispute(state: 'won', outcome: 'won', reason: 'fraudulent', evidence_due_at: nil,
                   evidence_submitted_at: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710repops@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710ro_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710ro_#{SecureRandom.hex(4)}",
      state: state, outcome: outcome, reason: reason, amount: 12.34, fee_amount: 15.0, currency: 'usd',
      store_id: store.id, payment: payment, order: order,
      evidence_due_at: evidence_due_at, evidence_submitted_at: evidence_submitted_at
    )
  end

  before { sign_in_as_superuser }

  it 'renders the store report card with win rate, deadline and reason breakdown' do
    make_dispute(state: 'won', outcome: 'won', reason: 'fraudulent',
                 evidence_due_at: 5.days.ago, evidence_submitted_at: 6.days.ago)
    make_dispute(state: 'lost', outcome: 'lost', reason: 'product_not_received')

    get PallasTrade.admin_disputes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Dispute operations report')
    expect(response.body).to include('Win rate')
    expect(response.body).to include('fraudulent')
    expect(response.body).to include('product_not_received')
    expect(response.body).to include('50.0%') # 1 won / (1 won + 1 lost)
  end

  it 'degrades to a visible warning (page still 200) when the report cannot be built' do
    make_dispute
    allow_any_instance_of(PallasTrade::Disputes::OpsReport)
      .to receive(:build_report).and_raise(StandardError, 'boom')

    get PallasTrade.admin_disputes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Partial or unavailable figures')
    expect(response.body).to include('report_unavailable:StandardError')
  end

  it 'writes nothing while rendering the report' do
    make_dispute
    before = {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      audits: PallasTrade::AuditLog.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count
    }

    get PallasTrade.admin_disputes_path

    expect({
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      audits: PallasTrade::AuditLog.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count
    }).to eq(before)
  end
end
