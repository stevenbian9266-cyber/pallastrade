# frozen_string_literal: true

require 'spec_helper'

# PRD-20260830-checkout AC-007（同一订单活动 PaymentSession 复用）
RSpec.describe PallasTrade::PaymentSessions::Start, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(
      :order,
      store: store,
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current,
      item_total: 10,
      total: 10,
      payment_state: 'balance_due'
    )
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  it 'returns the same active session for a replay with the same method and mode' do
    first = described_class.call(
      order: order,
      payment_method: payment_method,
      external_data: { mode: 'payment_intent' }
    )
    replay = described_class.call(
      order: order,
      payment_method: payment_method,
      external_data: { mode: 'payment_intent' }
    )

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value).to eq(first.value)
    expect(order.payment_sessions.count).to eq(1)
    expect(first.value.external_data['idempotency_key']).to match(/attempt-1\z/)
  end

  it 'calls the payment provider without holding the Order lock transaction' do
    order
    payment_method
    baseline_transactions = PallasTrade::Order.connection.open_transactions

    expect(payment_method).to receive(:create_payment_session).and_wrap_original do |method, **arguments|
      expect(PallasTrade::Order.connection.open_transactions).to eq(baseline_transactions)
      method.call(**arguments)
    end

    expect(described_class.call(order: order, payment_method: payment_method, external_data: {})).to be_success
  end

  it 'reconciles concurrent provider sessions to one active winner' do
    competing_session = nil
    duplicate_session = nil
    allow(payment_method).to receive(:create_payment_session).and_wrap_original do |method, **arguments|
      competing_session = method.call(**arguments)
      duplicate_session = method.call(**arguments)
      duplicate_session
    end

    result = described_class.call(order: order, payment_method: payment_method, external_data: {})

    expect(result).to be_success
    expect(result.value).to eq(competing_session)
    expect(duplicate_session.reload).to be_canceled
    expect(order.payment_sessions.active).to contain_exactly(competing_session)
  end

  it 'creates a new operation after the previous session reaches a terminal state' do
    first = described_class.call(order: order, payment_method: payment_method, external_data: {}).value
    first.fail

    retry_result = described_class.call(order: order, payment_method: payment_method, external_data: {})

    expect(retry_result).to be_success
    expect(retry_result.value).not_to eq(first)
    expect(retry_result.value.external_data['idempotency_key']).to match(/attempt-2\z/)
  end

  it 'rejects a payment method that is not available on the order store' do
    other_store = create(:store, code: "other_#{SecureRandom.hex(4)}")
    alien_method = create(:bogus_payment_method, store: other_store, active: true, display_on: 'both')

    result = described_class.call(order: order, payment_method: alien_method, external_data: {})

    expect(result).to be_failure
    expect(order.payment_sessions).to be_empty
  end

  # P0-3 (PRD FR-030): 金额变化后不得复用旧支付意图——即使旧 active 会话仍在。
  it 'does not reuse an active session when the amount changed, and issues a fresh operation key' do
    first = described_class.call(order: order, payment_method: payment_method, external_data: {}).value
    expect(first.external_data['idempotency_key']).to match(/amount-10\.0-attempt-1\z/)

    order.update_columns(item_total: 12, total: 12)
    order.reload

    second = described_class.call(order: order, payment_method: payment_method, external_data: {}).value

    expect(second).not_to eq(first)
    expect(order.payment_sessions.count).to eq(2)
    # attempt 计全部已持久化会话：金额 12 的创建拿到全新 key（不与 pending 的 amount-10 冲突）
    expect(second.external_data['idempotency_key']).to match(/amount-12\.0-attempt-2\z/)
    expect(second.amount).to eq(BigDecimal('12'))
  end

  # P0-3 (PRD FR-030): 复用只限新鲜窗口——超过 REUSE_WINDOW 的 active 会话视为 stale，
  # 不复用（创建新会话 + 新 operation key），避免拿到 provider 侧已过期的 client_secret。
  it 'does not reuse an active session older than the reuse window' do
    first = described_class.call(order: order, payment_method: payment_method, external_data: {}).value
    first.update_columns(created_at: (described_class::REUSE_WINDOW + 1.minute).ago)

    second = described_class.call(order: order, payment_method: payment_method, external_data: {}).value

    expect(second).not_to eq(first)
    expect(order.payment_sessions.count).to eq(2)
    expect(second.external_data['idempotency_key']).to match(/attempt-2\z/)
  end

  # CHK-P1-3 (PRD §12)：quote 作用域 Payment Start Gate。
  describe 'CHK-P1-3 quote gate' do
    # 真实标准流订单（line items + address + shipment）→ pending。
    let(:order) do
      o = create(:order_with_line_items, store: store, user: create(:user),
                                         line_items_price: 100, shipment_cost: 0)
      o.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                       completed_at: nil, payment_state: 'balance_due', payment_total: 0)
      PallasTrade::OrderUpdater.new(o).update
      o.reload
    end

    def quote!(order)
      PallasTrade::OrderCheckout::Recalculate.call(order: order)
      order.reload
    end

    it 'records price_version on the new session for an active quote (AC-303/305)' do
      quote!(order)

      result = described_class.call(order: order, payment_method: payment_method, external_data: {})

      expect(result).to be_success
      expect(result.value.external_data['price_version']).to eq(order.price_version)
      expect(result.value.external_data.key?('quote_refreshed')).to be false
    end

    it 'auto-refreshes an expired quote before starting and marks quote_refreshed (AC-303)' do
      quote!(order)
      order.update_columns(checkout_expires_at: 1.hour.ago)

      result = described_class.call(order: order, payment_method: payment_method, external_data: {})

      expect(result).to be_success
      expect(order.reload.checkout_expires_at).to be > Time.current
      expect(result.value.external_data['quote_refreshed']).to eq(true)
      expect(result.value.external_data['price_version']).to eq(order.reload.price_version)
    end

    it 'blocks payment start when a quoted order is missing checkout requirements (AC-304)' do
      quote!(order)
      order.update_columns(email: nil)

      result = described_class.call(order: order, payment_method: payment_method, external_data: {})

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('checkout_not_ready')
      expect(result.error.value[:missing_requirements]).to include('contact')
      expect(order.payment_sessions.count).to eq(0)
    end

    it 'leaves unquoted standard orders untouched (no quote lifecycle enforcement) (AC-305)' do
      result = described_class.call(order: order, payment_method: payment_method, external_data: {})

      expect(result).to be_success
      expect(order.payment_sessions.count).to eq(1)
      expect(result.value.external_data.key?('quote_refreshed')).to be false
    end
  end

  # CHK-P1-5 (PRD §12): expected-quote 409 conflict（Refresh 后比对）。
  describe 'CHK-P1-5 expected-quote conflict' do
    let(:order) do
      o = create(:order_with_line_items, store: store, user: create(:user),
                                         line_items_price: 100, shipment_cost: 0)
      o.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                       completed_at: nil, payment_state: 'balance_due', payment_total: 0)
      PallasTrade::OrderUpdater.new(o).update
      o.reload
    end

    def quote!(order)
      PallasTrade::OrderCheckout::Recalculate.call(order: order)
      order.reload
    end

    it 'starts payment when expected version/price_version match the active quote (AC-501)' do
      quote!(order)

      result = described_class.call(
        order: order, payment_method: payment_method, external_data: {},
        expected_version: order.checkout_version,
        expected_price_version: order.price_version
      )

      expect(result).to be_success
      expect(order.payment_sessions.count).to eq(1)
    end

    it 'fails with checkout_version_conflict + compact latest when version mismatches (AC-502)' do
      quote!(order)
      before_count = order.payment_sessions.count

      result = described_class.call(
        order: order, payment_method: payment_method, external_data: {},
        expected_version: order.checkout_version + 1,
        expected_price_version: order.price_version
      )

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('checkout_version_conflict')
      latest = result.error.value[:latest]
      expect(latest[:version]).to eq(order.checkout_version)
      expect(latest[:price_version]).to eq(order.price_version)
      expect(latest[:amount_due]).to eq(order.amount_due.to_s)
      expect(latest[:display_amount_due]).to eq(order.display_amount_due.to_s)
      expect(latest[:expires_at]).to eq(order.checkout_expires_at&.iso8601)
      expect(order.payment_sessions.count).to eq(before_count)
    end

    it 'fails when expected price_version mismatches even if version matches (AC-503)' do
      quote!(order)

      result = described_class.call(
        order: order, payment_method: payment_method, external_data: {},
        expected_version: order.checkout_version,
        expected_price_version: 'deadbeef00000000'
      )

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('checkout_version_conflict')
      expect(order.payment_sessions.count).to eq(0)
    end

    it 'auto-refreshes an expired quote before comparing, then conflicts on the bumped version (AC-504)' do
      quote!(order)
      order.update_columns(checkout_expires_at: 1.hour.ago)
      stale_version = order.checkout_version

      result = described_class.call(
        order: order, payment_method: payment_method, external_data: {},
        expected_version: stale_version,
        expected_price_version: order.price_version
      )

      # Refresh 续期且 checkout_version 递增 → 旧期望值冲突 → 409（客户端重读）
      expect(order.reload.checkout_expires_at).to be > Time.current
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('checkout_version_conflict')
      expect(result.error.value[:latest][:version]).to eq(order.checkout_version)
    end

    it 'passes after auto-refresh when only the (unchanged) price_version is expected (AC-504)' do
      quote!(order)
      order.update_columns(checkout_expires_at: 1.hour.ago)
      price_version = order.price_version

      result = described_class.call(
        order: order, payment_method: payment_method, external_data: {},
        expected_price_version: price_version
      )

      expect(order.reload.checkout_expires_at).to be > Time.current
      expect(result).to be_success
      expect(order.payment_sessions.count).to eq(1)
      expect(result.value.external_data['quote_refreshed']).to eq(true)
    end
  end
end
