# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B1) AC-001 / AC-003 / AC-004 / AC-010
# —— 控制台接线（B1.5）：提交历史 / 素材库·建议卡渲染；precheck 动作**零写**（不建回执、不写审计、不调 provider）。
RSpec.describe 'Admin Disputes Ops evidence operations (DSP-P7-10 B1)', type: :request do
  let!(:store) { create(:store, code: "p710_ops_#{SecureRandom.hex(4)}", default: true) }
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

  def make_dispute
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710ops@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710o_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710o_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_catalog(required: true)
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
      [{ key: 'customer_name', type: 'text', required: required }, { key: 'receipt', type: 'file' }]
    )
  end

  def write_counts
    {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      audits: PallasTrade::AuditLog.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      assets: PallasTrade::DisputeEvidenceAsset.count
    }
  end

  before { sign_in_as_superuser }

  describe 'AC-004 提交历史卡（只读）' do
    it 'renders the timeline with per-kind versions, provider receipt and key diff' do
      stub_catalog
      dispute = make_dispute
      PallasTrade::DisputeEvidenceSubmission.create!(
        dispute: dispute, kind: 'evidence_submitted', payload_digest: 'a' * 64,
        provider_status: 'under_review', provider_reference: 'dp_ops_v1', late: false,
        response_metadata: { 'evidence_keys' => %w[customer_name receipt] }
      )
      PallasTrade::DisputeEvidenceSubmission.create!(
        dispute: dispute, kind: 'evidence_submitted', payload_digest: 'b' * 64,
        provider_status: 'under_review', provider_reference: 'dp_ops_v2', late: true,
        response_metadata: { 'evidence_keys' => %w[customer_name product_description] }
      )

      get PallasTrade.admin_dispute_path(dispute)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Submission history')
      expect(response.body).to include('dp_ops_v1')
      expect(response.body).to include('dp_ops_v2')
      expect(response.body).to include('product_description') # 证据键（v2）
      expect(response.body).to include('(late)')
      expect(response.body).to include('added product_description')
      expect(response.body).to include('removed receipt')
    end

    it 'degrades to an empty-state line when nothing was submitted' do
      stub_catalog
      dispute = make_dispute

      get PallasTrade.admin_dispute_path(dispute)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Nothing has been submitted to the provider yet.')
    end
  end

  describe 'AC-001 / AC-002 素材库与建议卡（只读引用，不自动提交）' do
    it 'lists the store library and maps gateway catalogue entries onto stored assets' do
      stub_catalog
      PallasTrade::DisputeEvidenceAsset.create!(
        store: store, name: 'Delivery wording', kind: 'text', body: 'Delivered 2026-09-01',
        evidence_key: 'customer_name', reason_code: 'product_not_received'
      )
      dispute = make_dispute

      get PallasTrade.admin_dispute_path(dispute)

      expect(response.body).to include('Evidence library')
      expect(response.body).to include('Delivery wording')
      expect(response.body).to include('Suggested for this gateway')
      expect(response.body).to include('customer_name')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0) # 建议不会产生提交
    end

    it 'states that unsupported gateways get no suggestions instead of inventing them' do
      allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return([])
      dispute = make_dispute

      get PallasTrade.admin_dispute_path(dispute)

      expect(response.body).to include('This gateway declares no evidence catalogue, so no suggestions are made.')
    end
  end

  describe 'AC-003 precheck 动作（零写）' do
    it 'blocks a draft carrying an unknown evidence key with a readable message and writes nothing at all' do
      stub_catalog
      dispute = make_dispute
      before = write_counts

      expect_any_instance_of(payment_method.class).not_to receive(:submit_dispute_evidence)
      post PallasTrade.precheck_admin_dispute_path(dispute), params: { evidence: { totally_unknown: 'x' } }

      expect(response).to have_http_status(:see_other)
      expect(flash[:error]).to include('Draft check blocked')
      expect(write_counts).to eq(before)
    end

    it 'reports readiness for a valid draft without contacting the provider' do
      stub_catalog
      dispute = make_dispute
      before = write_counts

      post PallasTrade.precheck_admin_dispute_path(dispute), params: { evidence: { customer_name: 'Jane Doe' } }

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('Draft check passed')
      expect(write_counts).to eq(before)
    end

    it 'warns (does not block) when the operator confirms a late draft' do
      stub_catalog
      dispute = PallasTrade::Dispute.find(make_dispute.id)
      dispute.update!(evidence_due_at: 2.days.ago)

      post PallasTrade.precheck_admin_dispute_path(dispute),
           params: { evidence: { customer_name: 'Jane' }, late_confirmed: '1' }

      expect(flash[:success]).to include('Draft check passed')
      expect(flash[:warning]).to be_present
    end

    it 'blocks a late draft that has not been confirmed yet' do
      stub_catalog
      dispute = PallasTrade::Dispute.find(make_dispute.id)
      dispute.update!(evidence_due_at: 2.days.ago)

      post PallasTrade.precheck_admin_dispute_path(dispute), params: { evidence: { customer_name: 'Jane' } }

      expect(flash[:error]).to include('Draft check blocked')
    end
  end

  describe 'AC-010 铁律：控制台新面零资金/库存/订单写' do
    it 'keeps every ledger-facing table untouched across show + precheck' do
      stub_catalog
      dispute = make_dispute
      before = write_counts

      get PallasTrade.admin_dispute_path(dispute)
      post PallasTrade.precheck_admin_dispute_path(dispute), params: { evidence: { customer_name: 'Jane' } }
      post PallasTrade.precheck_admin_dispute_path(dispute), params: { evidence: {} }

      expect(write_counts).to eq(before)
      expect(dispute.reload.evidence_submitted_at).to be_nil
    end
  end
end
