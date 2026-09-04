# frozen_string_literal: true

require 'rails_helper'

# P0-6 (PRD FR-064): PallasTrade::Audit 写入服务。
RSpec.describe PallasTrade::Audit, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store) }

  it 'records an audit log with actor/resource/before/after metadata' do
    before_state = { active: false }
    after_state = { active: true }

    entry = described_class.record(
      actor: { type: 'PallasTrade::User', id: 42, label: 'admin@example.com' },
      action: 'gateway_credential_change',
      resource: payment_method,
      before: before_state,
      after: after_state,
      metadata: { keys: %w[secret_key] }
    )

    expect(entry).to be_persisted
    expect(entry.actor_type).to eq('PallasTrade::User')
    expect(entry.actor_id).to eq(42)
    expect(entry.action).to eq('gateway_credential_change')
    expect(entry.resource_type).to eq(payment_method.class.name)
    expect(entry.resource_id).to eq(payment_method.id)
    expect(entry.resource_prefixed_id).to eq(payment_method.prefixed_id)
    expect(entry.before).to eq('active' => false)
    expect(entry.after).to eq('active' => true)
    expect(entry.occurred_at).to be_present
  end

  it 'accepts a plain actor label (system / admin user string)' do
    entry = described_class.record(actor: 'system', action: 'webhook_replay',
                                   resource_type: 'PallasTrade::PaymentWebhookEvent', resource_id: 1)
    expect(entry.actor_label).to eq('system')
    expect(entry.actor_type).to be_nil
  end

  it 'does not raise when creation fails (audit must never break the main flow)' do
    expect do
      result = described_class.record(actor: 'system', action: nil)
      expect(result).to be_nil
    end.not_to raise_error
  end

  it 'scopes for_resource and recent' do
    described_class.record(actor: 'system', action: 'webhook_replay',
                           resource_type: 'PallasTrade::PaymentWebhookEvent', resource_id: 7)
    described_class.record(actor: 'system', action: 'refund',
                           resource_type: 'PallasTrade::Payment', resource_id: 8)

    expect(PallasTrade::AuditLog.for_resource('PallasTrade::Payment', 8).count).to eq(1)
    expect(PallasTrade::AuditLog.recent(1).first.action).to eq('refund')
  end
end
