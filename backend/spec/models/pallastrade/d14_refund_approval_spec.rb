# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，core 模型）
#   AC-001 ← FR-001：策略读取/归一化（未配置=不启用；非法阈值=保守全拦；币种限定）
#   AC-005 ← FR-004：`request_key` 唯一（请求级幂等的数据层兜底）
RSpec.describe PallasTrade::RefundApproval, type: :model do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 200, total: 200,
                   payment_state: 'balance_due')
  end

  def build_refund(amount: 120, **attrs)
    own_order = create(:order, store: store, state: 'pending', status: 'placed',
                             item_total: 200, total: 200, payment_state: 'balance_due')
    payment = create(:payment, order: own_order, amount: 200, state: 'completed',
                               response_code: "ch_d14_#{SecureRandom.hex(4)}")
    create(:refund, payment: payment, amount: amount, **attrs)
  end

  def build_approval(refund:, **attrs)
    PallasTrade::RefundApproval.create!(
      { store: store, refund: refund, status: 'pending', amount: refund.amount,
        currency: refund.currency, requester_id: nil }.merge(attrs)
    )
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'validates status, amount and the one-approval-per-refund rule' do
    refund = build_refund
    approval = build_approval(refund: refund)

    expect(approval).to be_pending
    expect(approval.decided?).to be(false)

    expect { build_approval(refund: refund) }.to raise_error(ActiveRecord::RecordInvalid)

    expect do
      build_approval(refund: build_refund, status: 'exploded')
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  # PRD-20260916-payments-d14-refund-approval AC-004
  it 'tracks requester / approver separation and decision state' do
    refund = build_refund
    approval = build_approval(refund: refund, requester_id: 7)

    expect(approval.requester?(7)).to be(true)
    expect(approval.requester?(8)).to be(false)
    expect(approval.policy_snapshot).to be_nil
    expect(approval.policy_limit).to be_nil

    approval.update!(status: 'approved', approver_id: 8, decided_at: Time.current,
                     policy_snapshot: { 'auto_approve_limit' => '100.0', 'currency' => 'USD' })

    expect(approval).to be_approved
    expect(approval).to be_decided
    expect(approval.policy_limit).to eq('100.0')
    expect(approval.policy_currency).to eq('USD')
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'filters the workbench queue by store, status and window' do
    other_store = create(:store, code: "d14_other_#{SecureRandom.hex(4)}", name: 'D14 Other',
                                 url: 'https://d14-other.example.com')
    pending = build_approval(refund: build_refund)
    decided = build_approval(refund: build_refund, status: 'rejected', decided_at: Time.current,
                                                       note: 'too large')
    build_approval(refund: build_refund, store: other_store)

    expect(described_class.where(store_id: store.id).filter_by(store_id: store.id).pluck(:id))
      .to contain_exactly(pending.id, decided.id)
    expect(described_class.filter_by(store_id: store.id, scope_filter: 'pending').pluck(:id)).to eq([pending.id])
    expect(described_class.filter_by(store_id: store.id, scope_filter: 'terminal').pluck(:id)).to eq([decided.id])
    expect(
      described_class.filter_by(store_id: store.id, from: 1.day.ago.beginning_of_day).pluck(:id)
    ).to contain_exactly(pending.id, decided.id)
    expect(described_class.filter_by(store_id: store.id, from: 1.day.from_now).pluck(:id)).to be_empty
  end

  # PRD-20260916-payments-d14-refund-approval AC-005
  it 'enforces a unique request_key on refunds at the database level' do
    payment = create(:payment, order: order, amount: 200, state: 'completed', response_code: 'ch_d14_key')
    create(:refund, payment: payment, amount: 10, request_key: 'rk_d14_unique')

    expect do
      create(:refund, payment: payment, amount: 10, request_key: 'rk_d14_unique')
    end.to raise_error(ActiveRecord::RecordNotUnique)

    # 无 request_key 的行不受唯一约束限制（既有行为不变）
    expect { create(:refund, payment: payment, amount: 10) }.not_to raise_error
  end
end
