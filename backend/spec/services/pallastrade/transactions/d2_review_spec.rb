# frozen_string_literal: true

# D2（PRD-20260917-payments-d2-manual-review-审核动作-通过并捕获-拒绝并释放）
# AC-001..008：manual_review 人工裁决（通过并捕获 / 拒绝并释放）。
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::Review, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:user) { create(:user) }
  let(:operator) { create(:admin_user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def attach_transaction(order, amount: order.total)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: order.currency.to_s, amount: amount
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                          role: 'primary', amount_snapshot: amount)
    tx
  end

  def manual_review_transaction(order)
    tx = attach_transaction(order)
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx.manual_review!
    tx
  end

  # 已授权未捕获（pending）——capture 分支的前置事实
  def authorized_payment(order, transaction, amount: order.total)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'pending', amount: amount,
                                             currency: order.currency.to_s, commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: amount,
                     state: 'pending', payment_session: session)
  end

  # 已完成（已捕获）资金事实——release 分支必须拒绝的存在性证据
  def captured_payment(order, transaction, amount: order.total)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'completed', amount: amount,
                                             currency: order.currency.to_s, commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: amount,
                     state: 'completed', payment_session: session)
  end

  def review(transaction, decision:, reason: 'ops verified with provider', actor: operator)
    described_class.call(transaction: transaction, decision: decision, reason: reason, actor: actor)
  end

  def review_audits(transaction, action)
    PallasTrade::AuditLog.where(action: action, resource_type: transaction.class.name,
                                resource_id: transaction.id)
  end

  describe 'AC-001 通过并捕获（capture）' do
    it 'captures the authorization, finalizes participants and completes the transaction' do
      order = pending_order
      tx = manual_review_transaction(order)
      payment = authorized_payment(order, tx)

      result = review(tx, decision: 'capture')

      expect(result).to be_success
      expect(result.value[:action]).to eq(:capture)
      expect(result.value[:already_applied]).to be(false)
      expect(payment.reload).to be_completed
      expect(tx.reload).to be_completed
      expect(order.reload).to be_completed
      expect(tx.transaction_orders.reload.first.completion_status).to eq('completed')
    end

    it 'AC-005 writes one captured audit row with before/after, decision, reason and actor' do
      order = pending_order
      tx = manual_review_transaction(order)
      authorized_payment(order, tx)

      review(tx, decision: 'capture')

      audits = review_audits(tx, described_class::AUDIT_CAPTURED)
      expect(audits.count).to eq(1)
      audit = audits.first
      expect(audit.before.to_h['state']).to eq('manual_review')
      expect(audit.after.to_h['state']).to eq('completed')
      expect(audit.metadata.to_h['decision']).to eq('capture')
      expect(audit.metadata.to_h['reason']).to eq('ops verified with provider')
      expect(audit.actor_id).to eq(operator.id)
    end

    it 'AC-003 refuses capture when no authorization is pending (transaction unchanged)' do
      order = pending_order
      tx = manual_review_transaction(order)

      result = review(tx, decision: 'capture')

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('no_pending_authorization')
      expect(tx.reload).to be_manual_review
      expect(order.reload).not_to be_completed
      expect(review_audits(tx, described_class::AUDIT_CAPTURED).count).to eq(0)
      expect(review_audits(tx, described_class::AUDIT_FAILED).count).to eq(1)
    end

    it 'AC-006 is idempotent per (transaction, decision): the replay applies nothing' do
      order = pending_order
      tx = manual_review_transaction(order)
      authorized_payment(order, tx)

      first = review(tx, decision: 'capture')
      second = review(tx, decision: 'capture')

      expect(first).to be_success
      expect(second).to be_success
      expect(second.value[:already_applied]).to be(true)
      expect(review_audits(tx, described_class::AUDIT_CAPTURED).count).to eq(1)
      expect(tx.reload).to be_completed
    end
  end

  describe 'AC-002 拒绝并释放（release）' do
    it 'voids the authorization, cancels participants and cancels the transaction with zero refunds' do
      order = pending_order
      tx = manual_review_transaction(order)
      payment = authorized_payment(order, tx)

      result = review(tx, decision: 'release')
      expect(result).to be_success
      expect(result.value[:action]).to eq(:release)
      expect(tx.reload).to be_canceled
      expect(order.reload).to be_canceled
      expect(payment.reload.state).to eq('void')
      expect(PallasTrade::Refund.count).to eq(0)
    end

    it 'AC-005 writes one released audit row with the canceled orders and voided payments' do
      order = pending_order
      tx = manual_review_transaction(order)
      payment = authorized_payment(order, tx)

      review(tx, decision: 'release')

      audits = review_audits(tx, described_class::AUDIT_RELEASED)
      expect(audits.count).to eq(1)
      expect(audits.first.before.to_h['state']).to eq('manual_review')
      expect(audits.first.after.to_h['state']).to eq('canceled')
      expect(audits.first.metadata.to_h['voided_payment_ids']).to eq([payment.id])
      expect(audits.first.metadata.to_h['canceled_order_numbers']).to eq([order.number])
    end

    it 'AC-007 refuses release when a captured payment exists (no guessing, zero refunds)' do
      order = pending_order
      tx = manual_review_transaction(order)
      captured_payment(order, tx)

      result = review(tx, decision: 'release')

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('paid_payment_present')
      expect(tx.reload).to be_manual_review
      expect(order.reload).not_to be_canceled
      expect(PallasTrade::Refund.count).to eq(0)
      expect(review_audits(tx, described_class::AUDIT_FAILED).count).to eq(1)
    end

    it 'AC-006 is idempotent per (transaction, decision)' do
      order = pending_order
      tx = manual_review_transaction(order)
      authorized_payment(order, tx)

      first = review(tx, decision: 'release')
      second = review(tx, decision: 'release')

      expect(first).to be_success
      expect(second.value[:already_applied]).to be(true)
      expect(review_audits(tx, described_class::AUDIT_RELEASED).count).to eq(1)
      expect(tx.reload).to be_canceled
    end
  end

  describe 'AC-008 守卫（状态 / 决策 / 原因）' do
    it 'refuses a transaction that is not in manual_review' do
      order = pending_order
      tx = attach_transaction(order)
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!

      result = review(tx, decision: 'capture')

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('transaction_not_reviewable')
      expect(result.error.value[:state]).to eq('recovery_required')
      expect(tx.reload).to be_recovery_required
    end

    it 'refuses an unknown decision' do
      order = pending_order
      tx = manual_review_transaction(order)

      result = review(tx, decision: 'refund_everything')

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('invalid_decision')
      expect(tx.reload).to be_manual_review
    end

    it 'requires a reason (both decisions) and writes only a failed audit' do
      order = pending_order
      tx = manual_review_transaction(order)
      authorized_payment(order, tx)

      result = review(tx, decision: 'capture', reason: '  ')

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('reason_required')
      expect(tx.reload).to be_manual_review
      expect(review_audits(tx, described_class::AUDIT_CAPTURED).count).to eq(0)
      expect(review_audits(tx, described_class::AUDIT_RELEASED).count).to eq(0)
    end

    it 'requires a reason for release as well' do
      order = pending_order
      tx = manual_review_transaction(order)

      result = review(tx, decision: 'release', reason: nil)

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('reason_required')
      expect(tx.reload).to be_manual_review
    end
  end

  describe 'AC-004 人工专用（自动路径永不调用）' do
    it 'is never referenced by jobs, sweepers or subscribers' do
      root = Rails.root
      files = Dir.glob(root.join('{app,pallastrade_gems,lib,config}/**/*.rb').to_s)
      automation = files.select { |path| File.basename(path).match?(/job|sweeper|subscriber/) }

      expect(automation.size).to be > 0
      expect(automation.select { |path| File.read(path).include?('Transactions::Review') }).to eq([])
    end

    it 'is only called from the admin controller (no other caller)' do
      files = Dir.glob(Rails.root.join('{app,pallastrade_gems,lib,config}/**/*.rb').to_s)
      callers = files.select { |path| File.read(path).match?(/Transactions::Review\.call|Transactions::Review\./) }

      expect(callers.map { |p| p.sub(%r{\A#{Regexp.escape(Rails.root.to_s)}/?}, '') })
        .to eq(['pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/transactions_controller.rb'])
    end

    it 'has no job class touching the manual review state machine events' do
      files = Dir.glob(Rails.root.join('{app,pallastrade_gems}/**/*job*.rb').to_s)
      offenders = files.select do |path|
        File.read(path).match?(/approve_after_review|release_after_review/)
      end

      expect(offenders).to eq([])
    end
  end
end
