# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion AC-004 AC-005
# `PallasTrade::Dispute` —— provider 发起的资金逆转的 durable aggregate（幂等 + 单向状态机）。
RSpec.describe PallasTrade::Dispute, type: :model do
  def build_dispute(**attrs)
    described_class.new({ provider: 'stripe', provider_dispute_reference: 'dp_1', state: 'opened',
                          amount: 10, currency: 'USD' }.merge(attrs))
  end

  describe 'validations（AC-004）' do
    it 'accepts a minimal valid dispute' do
      expect(build_dispute).to be_valid
    end

    it 'requires provider / reference / state' do
      dispute = described_class.new

      expect(dispute).not_to be_valid
      expect(dispute.errors.attribute_names).to include(:provider, :provider_dispute_reference, :state)
    end

    it 'enforces (provider, provider_dispute_reference) uniqueness' do
      described_class.create!(provider: 'stripe', provider_dispute_reference: 'dp_dup',
                              state: 'opened', amount: 5, currency: 'USD')

      duplicate = build_dispute(provider_dispute_reference: 'dp_dup')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.attribute_names).to include(:provider_dispute_reference)
    end

    it 'rejects unknown states / kinds / attention reasons' do
      expect(build_dispute(state: 'bogus')).not_to be_valid
      expect(build_dispute(kind: 'bogus')).not_to be_valid
      expect(build_dispute(attention_reason: 'bogus')).not_to be_valid
    end

    it 'allows zero amount (malformed provider payload must not lose the event) but rejects negatives' do
      expect(build_dispute(amount: 0)).to be_valid
      expect(build_dispute(amount: -1)).not_to be_valid
    end

    it 'exposes a dsp_ prefixed id' do
      dispute = described_class.create!(provider: 'stripe', provider_dispute_reference: 'dp_prefix',
                                        state: 'opened', amount: 1, currency: 'USD')

      expect(dispute.prefixed_id).to start_with('dsp_')
    end
  end

  describe '.upsert_from_event!（AC-005）' do
    it 'creates once and updates the same row on subsequent events' do
      first = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_upsert',
        attributes: { state: 'opened', amount: 12.5, currency: 'USD', kind: 'chargeback' }
      )
      second = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_upsert',
        attributes: { state: 'opened', evidence_due_at: Time.zone.now + 3.days }
      )

      expect(second.id).to eq(first.id)
      expect(described_class.where(provider: 'stripe', provider_dispute_reference: 'dp_upsert').count).to eq(1)
      expect(second.reload.evidence_due_at).to be_present
      expect(second.currency).to eq('USD')
    end

    it 'never overwrites existing facts with nil' do
      dispute = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_nil',
        attributes: { state: 'opened', amount: 20, currency: 'EUR', provider_charge_reference: 'ch_1' }
      )

      described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_nil',
        attributes: { provider_charge_reference: nil, currency: nil, reason: 'fraudulent' }
      )

      expect(dispute.reload.provider_charge_reference).to eq('ch_1')
      expect(dispute.currency).to eq('EUR')
      expect(dispute.reason).to eq('fraudulent')
    end
  end

  describe '#transition_to!（状态单向收敛，AC-005）' do
    it 'moves along allowed edges and records resolved_at for terminal states' do
      dispute = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_state',
        attributes: { state: 'opened', amount: 9, currency: 'USD' }
      )

      expect(dispute.transition_to!('needs_response')).to be(true)
      expect(dispute.transition_to!('submitted')).to be(true)
      expect(dispute.transition_to!('under_review')).to be(true)
      expect(dispute.transition_to!('won')).to be(true)

      expect(dispute.reload).to be_won
      expect(dispute.resolved_at).to be_present
      expect(dispute).to be_terminal
    end

    it 'is idempotent for the same state' do
      dispute = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_same',
        attributes: { state: 'opened', amount: 3, currency: 'USD' }
      )

      expect(dispute.transition_to!('opened')).to be(false)
    end

    it 'raises InvalidTransition for illegal edges / unknown states' do
      dispute = described_class.upsert_from_event!(
        provider: 'stripe', reference: 'dp_illegal',
        attributes: { state: 'won', amount: 3, currency: 'USD' }
      )

      expect { dispute.transition_to!('needs_response') }.to raise_error(described_class::InvalidTransition)
      expect { dispute.transition_to!('bogus') }.to raise_error(described_class::InvalidTransition)
    end
  end

  # PRD-20260913-payments-dsp-p7-7-admin-disputes-console
  # AC-P77-15 —— Admin Ops 查询能力：店铺作用域（防跨店泄露）+ Ransack 白名单（列表过滤/排序生效）
  describe 'Admin Ops query surface (DSP-P7-7)' do
    let(:store) { create(:store, code: 'dispute_scope_store', default: true) }
    let(:other_store) { create(:store, code: 'dispute_scope_other') }

    def scoped_dispute(target_store:, state: 'opened', reference:)
      described_class.create!(
        provider: 'stripe', provider_dispute_reference: reference,
        state: state, amount: 10, currency: 'usd', store_id: target_store.id
      )
    end

    it 'AC-P77-15 for_store 只返回该店争议' do
      mine = scoped_dispute(target_store: store, reference: 'dp_scope_mine')
      scoped_dispute(target_store: other_store, reference: 'dp_scope_theirs')

      expect(described_class.for_store(store).pluck(:id)).to eq([mine.id])
    end

    it 'AC-P77-15 ransack 白名单覆盖列表过滤所需列' do
      whitelisted = described_class.ransackable_attributes

      expect(whitelisted).to include('state', 'attention_reason', 'evidence_due_at', 'created_at')
      expect(described_class.ransack(state_cont: 'lost').result.to_sql).to include('state')
    end
  end
end
