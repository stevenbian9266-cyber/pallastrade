# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-3 ← FR-1：手工汇率 upsert 幂等（同身份键 = 更新原行）+ 撤销保留历史 + 审计
RSpec.describe PallasTrade::Currencies::Rates::Upsert do
  let!(:store) { create(:store, code: "d13d_up_#{SecureRandom.hex(4)}") }

  def upsert(**attrs)
    described_class.call(**{ store: store, base_currency: 'USD', quote_currency: 'CNY', rate: 7.1,
                             source: 'manual' }.merge(attrs))
  end

  it 'creates a rate row and records an audit entry' do
    expect { upsert }.to change(PallasTrade::CurrencyRate, :count).by(1)

    row = PallasTrade::CurrencyRate.last
    expect(row.base_currency).to eq('USD')
    expect(row.quote_currency).to eq('CNY')
    expect(row.rate.to_d).to eq(7.1.to_d)
    expect(row.priority).to eq(10)
    expect(row.store_id).to eq(store.id)
    expect(PallasTrade::AuditLog.where(action: 'currency_rate_changed').count).to be >= 1
  end

  it 'is idempotent: the same identity key updates the existing row instead of creating a second one' do
    upsert(rate: 7.1)
    first = PallasTrade::CurrencyRate.last

    expect { upsert(rate: 7.25, note: 'updated') }.not_to change(PallasTrade::CurrencyRate, :count)

    expect(first.reload.rate.to_d).to eq(7.25.to_d)
    expect(first.note).to eq('updated')
  end

  it 'keeps separate rows for different sources, effective windows and store scopes' do
    upsert(source: 'manual')
    upsert(source: 'provider')
    upsert(source: 'manual', effective_from: Time.zone.parse('2026-09-01'))
    upsert(source: 'manual', store: nil)

    expect(PallasTrade::CurrencyRate.count).to eq(4)
  end

  it 'soft revokes and keeps the historical row' do
    upsert
    row = PallasTrade::CurrencyRate.last

    expect { upsert(revoke: true, actor: 'ops') }.not_to change(PallasTrade::CurrencyRate, :count)

    expect(row.reload.status).to eq('revoked')
    expect(row.revoked_at).to be_present
    expect(PallasTrade::AuditLog.where(action: 'currency_rate_revoked').count).to be >= 1
    expect(described_class.call(store: store, base_currency: 'USD', quote_currency: 'CNY', rate: 7.1)
             .value[:rate].status).to eq('revoked')
  end

  it 'fails on invalid input without writing a row' do
    expect { upsert(rate: -1) }.not_to change(PallasTrade::CurrencyRate, :count)
    result = upsert(rate: -1)
    expect(result).not_to be_success
  end
end
