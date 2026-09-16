# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13-reconciliation-cases（切片1，core 模型）
#   AC-001 ← FR-001：差异类型 / 严重级确定性映射；签名与去重键；备注时间线；状态流转（关单/重开/指派）
RSpec.describe PallasTrade::ReconciliationCase, type: :model do
  let(:store) { @default_store }
  let(:transaction) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                             currency: store.default_currency.to_s, amount: 100)
  end

  def build_case(**attrs)
    described_class.create!(
      { store: store, kind: 'transaction', commerce_transaction: transaction,
        status: 'open', difference_type: 'amount_mismatch', severity: 'critical',
        dedupe_key: "txn:#{transaction.id}:#{SecureRandom.hex(4)}",
        detected_at: Time.current, last_seen_at: Time.current }.merge(attrs)
    )
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  describe '.difference_type_for' do
    {
      %w[MISMATCH AMOUNT_MISMATCH] => 'amount_mismatch',
      %w[MISMATCH CURRENCY_MISMATCH] => 'amount_mismatch',
      %w[MISMATCH ALLOCATION_MISMATCH] => 'allocation_mismatch',
      %w[MISMATCH REFUND_MISMATCH] => 'refund_mismatch',
      %w[NEEDS_ATTENTION LOCAL_PAYMENT_MISSING] => 'one_sided',
      %w[NEEDS_ATTENTION PROVIDER_PAYMENT_MISSING] => 'one_sided',
      %w[PENDING SETTLEMENT_PENDING] => 'settlement_pending',
      %w[NEEDS_ATTENTION JOURNAL_POSTING_MISSING] => 'journal_missing',
      %w[NEEDS_ATTENTION PROVIDER_UNAVAILABLE] => 'provider_issue',
      %w[NEEDS_ATTENTION UNLINKED_LEGACY_PAYMENT] => 'duplicate'
    }.each do |(status, reason), expected|
      it "maps #{reason} to #{expected}" do
        expect(described_class.difference_type_for(status: status, reasons: [reason])).to eq(expected)
      end
    end

    it 'falls back to needs_attention and marks unsupported providers explicitly' do
      expect(described_class.difference_type_for(status: 'NEEDS_ATTENTION', reasons: [])).to eq('needs_attention')
      expect(described_class.difference_type_for(status: 'UNSUPPORTED', reasons: ['X'])).to eq('unsupported')
    end
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  describe '.severity_for / .signature_for / .dedupe_key_for' do
    it 'maps reconciliation status to severity' do
      expect(described_class.severity_for(status: 'MISMATCH')).to eq('critical')
      expect(described_class.severity_for(status: 'NEEDS_ATTENTION')).to eq('attention')
      expect(described_class.severity_for(status: 'PENDING')).to eq('info')
      expect(described_class.severity_for(status: 'UNSUPPORTED')).to eq('info')
    end

    it 'builds a stable signature from sorted distinct reason codes' do
      expect(described_class.signature_for(status: 'MISMATCH', reasons: %w[B A A])).to eq('A+B')
      expect(described_class.signature_for(status: 'MISMATCH', reasons: [])).to eq('MISMATCH')
    end

    it 'builds the dedupe key from transaction and signature' do
      expect(described_class.dedupe_key_for(transaction_id: 7, signature: 'A+B')).to eq('txn:7:A+B')
    end
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  it 'enforces a unique dedupe key' do
    case_record = build_case
    duplicate = described_class.new(
      store: store, kind: 'transaction', commerce_transaction: transaction, status: 'open',
      difference_type: 'amount_mismatch', severity: 'critical', dedupe_key: case_record.dedupe_key,
      detected_at: Time.current, last_seen_at: Time.current
    )

    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordInvalid, /Dedupe key/)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  it 'keeps notes in chronological order and destroys them with the case' do
    case_record = build_case
    later = case_record.notes.create!(body: 'second', created_at: 2.hours.from_now)
    earlier = case_record.notes.create!(body: 'first', created_at: 1.hour.ago)

    expect(case_record.notes.reload.chronological.map(&:body)).to eq(%w[first second])

    ids = [later.id, earlier.id]
    case_record.destroy!

    expect(PallasTrade::ReconciliationCaseNote.where(id: ids)).to be_empty
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  it 'closes with a resolution source, keeps it closed and reopens on demand' do
    case_record = build_case
    case_record.close!(status: 'explained', source: 'human', note: 'provider confirmed timing')

    expect(case_record.status).to eq('explained')
    expect(case_record.resolution_source).to eq('human')
    expect(case_record.resolution_note).to eq('provider confirmed timing')
    expect(case_record.resolved_at).to be_present
    expect(case_record.human_resolved?).to be(true)
    expect(case_record.in_queue?).to be(false)

    case_record.reopen!
    expect(case_record.status).to eq('open')
    expect(case_record.resolved_at).to be_nil
    expect(case_record.resolution_source).to be_nil
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  it 'refuses unsupported close statuses' do
    case_record = build_case

    expect { case_record.close!(status: 'open', source: 'human') }.
      to raise_error(ArgumentError, /Unsupported close status/)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-001
  it 'assigns and unassigns a teammate' do
    case_record = build_case
    admin = create(:admin_user, password: 'secret', password_confirmation: 'secret')

    case_record.assign_to!(admin)
    expect(case_record.reload.assignee_id).to eq(admin.id)

    case_record.assign_to!(nil)
    expect(case_record.reload.assignee_id).to be_nil
  end
end
