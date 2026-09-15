# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d9-支付凭据与环境（切片1）
#   AC-005 ← FR-005：30 / 7 / 1 天阈值告警（写 metadata + 审计），同级别幂等、升级重新告警
RSpec.describe PallasTrade::PaymentMethods::CredentialExpiryCheckJob, type: :job do
  let(:store) { create(:store, code: "d9_job_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD') }
  let!(:provider) do
    create(:credit_card_payment_method, store: store, active: true,
                                        metadata: {
                                          'credentials' => {
                                            'dummy_secret_key' => { 'expires_on' => 5.days.from_now.to_date.iso8601 }
                                          }
                                        })
  end

  def alerts
    PallasTrade::AuditLog.where(action: 'payment_method_credential_alert')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-005
  it 'alerts once per level, writes metadata + audit, and stays idempotent' do
    expect { described_class.new.perform(store_id: store.id) }.to change { alerts.count }.by(1)

    stored = provider.reload.metadata['credential_alerts']
    expect(stored.dig('dummy_secret_key', 'level')).to eq('7d')

    # 同级别重复巡检不重复告警
    expect { described_class.new.perform(store_id: store.id) }.not_to change { alerts.count }
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-005
  it 'escalates when the credential passes the next threshold' do
    described_class.new.perform(store_id: store.id)

    expect { described_class.new.perform(store_id: store.id, now: 10.days.from_now) }.to change { alerts.count }.by(1)

    expect(provider.reload.metadata.dig('credential_alerts', 'dummy_secret_key', 'level')).to eq('expired')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-005
  it 'ignores providers without credential expiry metadata' do
    provider.update!(metadata: {})

    expect { described_class.new.perform(store_id: store.id) }.not_to change { alerts.count }
  end
end
