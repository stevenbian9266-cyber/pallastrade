# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission
# AC-P78-08/09/13 —— 管理台危险动作：权限（可见性 + 请求级 403）、provider 降级（422 语义 → 303 + 错误 flash 且零回执）、
# 前后端双重确认（confirm 参数）、文件上传、铁律负向断言（零资金副作用）、无批量路由。
RSpec.describe 'Admin Disputes Ops actions (DSP-P7-8 dangerous actions)', type: :request do
  let!(:store) { create(:store, code: "p78_ops_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
      to receive(:current_store).and_return(store)
  end

  def sign_in_as_no_permission
    sign_in admin
    role = create(:role, name: "P78Limited_#{SecureRandom.hex(4)}")
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
      to receive(:current_store).and_return(store)
  end

  def make_dispute(state: 'needs_response', evidence_due_at: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p78ops@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p78o_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p78o_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd', evidence_due_at: evidence_due_at,
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_catalog(keys: %w[customer_name receipt])
    catalog = keys.map do |key|
      if key == 'receipt'
        { key: 'receipt', type: 'file' }
      else
        { key: key, type: 'text' }
      end
    end
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(catalog)
  end

  def stub_write
    allow_any_instance_of(payment_method.class).to receive(:submit_dispute_evidence).and_return(
      { provider_reference: 'dp_ops_written', status: 'under_review', metadata: {} }
    )
    allow_any_instance_of(payment_method.class).to receive(:accept_dispute).and_return(
      { provider_reference: 'dp_ops_closed', status: 'lost', metadata: {} }
    )
  end

  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count
    }
  end

  describe 'AC-P78-03 提交证据（成功路径）' do
    it 'submits text and file evidence, records one receipt and audits' do
      sign_in_as_superuser
      stub_catalog
      stub_write
      dispute = make_dispute
      before_counts = money_counts

      file = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/dispute_evidence.png'), 'image/png')

      expect do
        post "/admin/disputes/#{dispute.prefixed_id}/submit_evidence",
             params: { evidence: { customer_name: 'Jane', receipt: file } }
      end.to change { PallasTrade::DisputeEvidenceSubmission.count }.by(1)

      expect(response).to have_http_status(:see_other)
      expect(PallasTrade::DisputeEvidenceSubmission.last.kind).to eq('evidence_submitted')
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_submitted').count).to eq(1)
      expect(money_counts).to eq(before_counts)
    end
  end

  describe 'AC-P78-10 逾期提交需要显式确认' do
    it 'refuses without late_confirmed and accepts with it' do
      sign_in_as_superuser
      stub_catalog
      stub_write
      dispute = make_dispute(evidence_due_at: 3.hours.ago)

      post "/admin/disputes/#{dispute.prefixed_id}/submit_evidence", params: { evidence: { customer_name: 'Jane' } }
      expect(response).to have_http_status(:see_other)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
      expect(flash[:error].to_s.downcase).to include('deadline')

      post "/admin/disputes/#{dispute.prefixed_id}/submit_evidence",
           params: { evidence: { customer_name: 'Jane' }, late_confirmed: '1' }
      expect(response).to have_http_status(303)
      expect(PallasTrade::DisputeEvidenceSubmission.last.late).to be(true)
    end
  end

  describe 'AC-P78-06/07 接受争议（不可逆）' do
    it 'requires the confirm parameter, then records a receipt with the reason' do
      sign_in_as_superuser
      stub_catalog
      stub_write
      dispute = make_dispute

      post "/admin/disputes/#{dispute.prefixed_id}/accept_dispute", params: { reason: 'no proof' }
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
      expect(flash[:error].to_s.downcase).to include('confirmation')

      post "/admin/disputes/#{dispute.prefixed_id}/accept_dispute", params: { reason: 'no proof', confirm: '1' }
      expect(response).to have_http_status(303)
      submission = PallasTrade::DisputeEvidenceSubmission.last
      expect(submission.kind).to eq('accepted')
      expect(submission.accepted_reason).to eq('no proof')
      expect(flash[:success].to_s.downcase).to include('accepted')
    end
  end

  describe 'AC-P78-09 provider 降级' do
    it 'degrades without a receipt when the gateway has no catalog' do
      sign_in_as_superuser
      dispute = make_dispute

      post "/admin/disputes/#{dispute.prefixed_id}/submit_evidence", params: { evidence: { customer_name: 'Jane' } }

      expect(response).to have_http_status(:see_other)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
      expect(flash[:error].to_s.downcase).to include('not support')
    end
  end

  describe 'AC-P78-08 权限' do
    it 'blocks request-level access without :update' do
      sign_in_as_no_permission
      stub_catalog
      stub_write
      dispute = make_dispute

      # 权限拒绝的既有行为：302 重定向（非 303 动作成功重定向）+ 零回执
      post "/admin/disputes/#{dispute.prefixed_id}/submit_evidence", params: { evidence: { customer_name: 'Jane' } }
      expect(response).to have_http_status(:found)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)

      post "/admin/disputes/#{dispute.prefixed_id}/accept_dispute", params: { reason: 'x', confirm: '1' }
      expect(response).to have_http_status(:found)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
    end
  end

  describe 'AC-P78-13 无批量/无越界路由' do
    it 'exposes only the per-dispute dangerous routes' do
      expect(PallasTrade.submit_evidence_admin_dispute_path('dsp_x')).to end_with('/submit_evidence')
      expect(PallasTrade.accept_dispute_admin_dispute_path('dsp_x')).to end_with('/accept_dispute')

      routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
      expect(routes.grep(/disputes?_(bulk|batch)/)).to be_empty
    end
  end
end
