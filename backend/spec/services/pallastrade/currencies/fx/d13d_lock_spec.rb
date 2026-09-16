# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-5 ← FR-3：下单锁汇（加点后有效汇率、同币种跳过、无汇率不写行、幂等、策略关闭）
RSpec.describe PallasTrade::Currencies::Fx::Lock do
  let!(:store) do
    create(:store, code: "d13d_lock_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY,EUR')
  end
  let!(:order) { create(:order, store: store, currency: 'CNY', number: "R#{SecureRandom.hex(4)}") }

  def lock(**opts)
    described_class.call(**{ order: order }.merge(opts))
  end

  context 'without a resolvable rate' do
    it 'does not write a snapshot and reports no_rate' do
      expect { lock }.not_to change(PallasTrade::FxSnapshot, :count)

      expect(lock.value[:snapshot]).to be_nil
      expect(lock.value[:signals]).to eq(['no_rate'])
    end
  end

  context 'with a resolvable rate' do
    before { create(:currency_rate, store: store, source: 'manual', rate: BigDecimal('7.1')) }

    it 'locks the display rate and the up-charged effective rate' do
      store.update!(private_metadata: { 'fx_policy' => { 'up_charge_percent' => 0.5 } })

      expect { lock }.to change(PallasTrade::FxSnapshot, :count).by(1)

      snapshot = PallasTrade::FxSnapshot.last
      expect(snapshot.display_rate.to_d).to eq(BigDecimal('7.1'))
      expect(snapshot.up_charge_percent.to_d).to eq(BigDecimal('0.5'))
      expect(snapshot.effective_rate.to_d).to eq(BigDecimal('7.1355'))
      expect(snapshot.rate_source).to eq('manual')
      expect(snapshot.variance_status).to eq('pending')
      expect(snapshot.locked_on).to eq('order.submitted')
      expect(snapshot.metadata['order_number']).to eq(order.number)
      expect(PallasTrade::AuditLog.where(action: 'fx_snapshot_locked').count).to eq(1)
    end

    it 'is idempotent for the same order and currency pair' do
      lock
      expect { lock }.not_to change(PallasTrade::FxSnapshot, :count)

      expect(PallasTrade::FxSnapshot.last.occurrences).to eq(2)
      expect(PallasTrade::AuditLog.where(action: 'fx_snapshot_locked').count).to eq(1)
    end

    it 'skips same-currency orders' do
      usd_order = create(:order, store: store, currency: 'USD')

      result = described_class.call(order: usd_order)

      expect(result.value[:snapshot]).to be_nil
      expect(result.value[:signals]).to eq(['same_currency'])
      expect(PallasTrade::FxSnapshot.count).to eq(0)
    end

    it 'respects the store policy switch' do
      store.update!(private_metadata: { 'fx_policy' => { 'enabled' => false } })

      expect { lock }.not_to change(PallasTrade::FxSnapshot, :count)
      expect(lock.value[:signals]).to eq(['disabled'])
    end

    it 'can lock an explicit quote currency' do
      result = lock(quote_currency: 'CNY')

      expect(result.value[:snapshot].quote_currency).to eq('CNY')
    end

    it 'requires an order' do
      expect(described_class.call(order: nil)).not_to be_success
    end
  end
end
