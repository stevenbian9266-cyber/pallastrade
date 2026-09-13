# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B3 / FR-008) AC-008 / AC-010
# —— 退货/补货**人工入口**：只跳转到既有订单售后流程；无锚点订单时显式提示；
# 争议页面渲染零库存/订单/资金写。
RSpec.describe 'Admin Disputes Ops return entry (DSP-P7-10 B3)', type: :request do
  let!(:store) { create(:store, code: "p710_rma_#{SecureRandom.hex(4)}", default: true) }
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

  def make_order
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'paid',
                   currency: store.default_currency, email: 'p710rma@example.com')
  end

  def make_dispute(order: nil)
    payment = order && create(:payment, order: order, payment_method: payment_method, amount: 100,
                                         state: 'completed', response_code: "pi_p710rm_#{SecureRandom.hex(4)}",
                                         source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710rm_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  before { sign_in_as_superuser }

  it 'AC-008 exposes a manual link into the existing order returns flow' do
    order = make_order
    dispute = make_dispute(order: order)

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Returns / restock (manual)')
    expect(response.body).to include('Open return / restock flow')
    expect(response.body).to include(PallasTrade.parent_order_returns_admin_order_path(order))
  end

  it 'AC-008 states plainly when there is no anchored order to return against' do
    dispute = make_dispute(order: nil)

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('No anchored order on this dispute')
    expect(response.body).not_to include('Open return / restock flow')
  end

  it 'AC-010 rendering the entry moves no stock, order or money' do
    order = make_order
    dispute = make_dispute(order: order)
    before = {
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_movements: PallasTrade::StockMovement.count,
      orders: PallasTrade::Order.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      submissions: PallasTrade::DisputeEvidenceSubmission.count
    }

    get PallasTrade.admin_dispute_path(dispute)

    expect({
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_movements: PallasTrade::StockMovement.count,
      orders: PallasTrade::Order.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      submissions: PallasTrade::DisputeEvidenceSubmission.count
    }).to eq(before)
    expect(dispute.reload.state).to eq('needs_response')
  end
end
