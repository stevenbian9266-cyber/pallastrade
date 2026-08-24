# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-002
require 'rails_helper'

RSpec.describe PallasTrade::PaymentGroups::Create, type: :service do
  let(:store) { create(:store, code: 'pg_create_test') }
  let(:user) { create(:user) }

  def unpaid_order(currency: 'USD')
    # 用 order_with_line_items（after_create 调 update_with_updater! 重算 total），
    # 避免 order_with_totals 不重算 total（total=0 → outstanding_balance<=0 → 误判
    # order_already_paid）。
    create(:order_with_line_items, store: store, user: user, currency: currency, status: 'placed',
                                   payment_state: 'balance_due', completed_at: nil)
  end

  describe '#call' do
    it 'creates a payment group from multiple unpaid order ids' do
      o1 = unpaid_order
      o2 = unpaid_order

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_success
      group = result.value
      expect(group.prefixed_id).to start_with('pg_')
      expect(group.orders).to match_array([o1, o2])
      expect(group.currency).to eq('USD')
      expect(group.amount).to eq(o1.total + o2.total)
    end

    it 'rejects mixed currencies' do
      o1 = unpaid_order(currency: 'USD')
      o2 = unpaid_order(currency: 'EUR')

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:mixed_currency)
    end

    it 'rejects orders not owned by the user' do
      o1 = unpaid_order
      other = create(:user)
      o2 = unpaid_order
      o2.update_column(:user_id, other.id)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:orders_not_owned)
    end

    it 'rejects already-paid orders' do
      o1 = unpaid_order
      o2 = unpaid_order
      o2.update_columns(payment_state: 'paid', payment_total: o2.total)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:order_already_paid)
    end

    it 'rejects canceled orders' do
      o1 = unpaid_order
      o2 = unpaid_order
      # canceled? 由 state_machine 检查 state（非 status 列）
      o2.update_columns(state: 'canceled', canceled_at: Time.current)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:order_canceled)
    end

    it 'rejects unknown order ids' do
      result = described_class.call(store: store, order_ids: ['or_does_not_exist'], user: user)
      expect(result).to be_failure
      expect(result.error.value).to eq(:orders_not_found)
    end
  end

  # PRD-20260824-checkout-合并支付复用已有支付组继续支付-订单已在支付组时不报错
  # AC-001~AC-005：订单已在 active 支付组时幂等复用，不再报 order_in_active_group。
  describe 'idempotent reuse of an active payment group' do
    def create_active_group(orders, created_at: Time.current)
      group = PallasTrade::PaymentGroup.create!(
        store: store,
        customer: user,
        currency: orders.first.currency,
        status: 'pending',
        amount: orders.sum(&:total),
        created_at: created_at
      )
      orders.each { |o| o.update!(payment_group_id: group.id) }
      group
    end

    it 'returns the existing active group instead of failing (AC-001)' do
      o1 = unpaid_order
      group = create_active_group([o1])

      result = described_class.call(store: store, order_ids: [o1.prefixed_id], user: user)

      expect(result).to be_success
      expect(result.value.id).to eq(group.id)
      expect(result.value.orders).to match_array([o1])
    end

    it 'does not create a new group on repeat calls (AC-002)' do
      o1 = unpaid_order
      create_active_group([o1])

      expect do
        described_class.call(store: store, order_ids: [o1.prefixed_id], user: user)
      end.not_to change(PallasTrade::PaymentGroup.where(store: store), :count)
    end

    it 'reuses the most recently created group when orders span multiple groups (AC-003)' do
      o1 = unpaid_order
      o2 = unpaid_order
      old_group = create_active_group([o1], created_at: 1.hour.ago)
      recent_group = create_active_group([o2], created_at: 10.minutes.ago)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_success
      expect(result.value.id).to eq(recent_group.id)
      expect(result.value.orders).to match_array([o1, o2])
      expect(o1.reload.payment_group_id).to eq(recent_group.id)
      # 被清空的旧组标记 canceled，不残留 pending 空组
      expect(old_group.reload.status).to eq('canceled')
    end

    it 'merges not-yet-grouped orders into the existing group and recomputes the amount (AC-004)' do
      o1 = unpaid_order
      o2 = unpaid_order
      group = create_active_group([o1])

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_success
      expect(result.value.id).to eq(group.id)
      expect(result.value.orders).to match_array([o1, o2])
      expect(result.value.amount).to eq(o1.total + o2.total)
    end

    it 'rejects when the reused group currency does not match the order currency (AC-005)' do
      o1 = unpaid_order(currency: 'USD')
      # 人为构造异常数据：USD 订单挂到 EUR 组
      group = PallasTrade::PaymentGroup.create!(
        store: store, customer: user, currency: 'EUR', status: 'pending', amount: 0
      )
      o1.update!(payment_group_id: group.id)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:mixed_currency)
    end

    it 'still creates a fresh group when no order is in an active group (AC-007 regression)' do
      o1 = unpaid_order
      o2 = unpaid_order

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_success
      expect(result.value.prefixed_id).to start_with('pg_')
    end
  end
end
