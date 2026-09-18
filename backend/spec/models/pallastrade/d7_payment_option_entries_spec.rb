# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-payments-d7-payment-section-express（切片1，core 读模型）
#   AC-001 ← FR-001：选项化 provider → 入口级投影（顺序 = position，字段齐备）
#   AC-002 ← FR-001/NFR-002：未选项化 provider → 1 条 entry（默认入口，零回归）
#   AC-003 ← FR-001：停用入口不出现在 entries
#   AC-005 ← FR-002：provider 级 group/position 与首个生效入口一致
#   AC-006 ← FR-003（读模型部分）：frontend_kind / group 映射（inline=card / express=wallet / manual）
RSpec.describe 'D7 payment option entries', type: :model do
  # 用**真实 Stripe 目录**（声明 card / apple_pay / google_pay 能力）+
  # 每个 example 独立门店（`@default_store` 是跨 example 共享对象，写 metadata 会泄漏）。
  let(:store) do
    create(:store, code: "d7-entries-#{SecureRandom.hex(4)}", name: 'D7 Entries Store',
                   default: false, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d7-entries.example.com', mail_from_address: 'no-reply@d7-entries.example.com')
  end

  def optionized_provider(options, name: 'D7 provider')
    create(:stripe_gateway, store: store, active: true, display_on: 'front_end', name: name,
                            metadata: { 'optionized' => true, 'options' => options })
  end

  # PRD-20260918-payments-d7-payment-section-express AC-001
  it 'expands every enabled entry in position order with entry-level fields' do
    provider = optionized_provider([
      { 'kind' => 'google_pay', 'active' => true, 'position' => 3, 'frontend_kind' => 'express',
        'display_name' => 'Google Pay' },
      { 'kind' => 'card', 'active' => true, 'position' => 1, 'frontend_kind' => 'inline',
        'display_name' => '信用卡' },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'frontend_kind' => 'express',
        'display_name' => 'Apple Pay' }
    ])

    entries = provider.payment_option_entries

    expect(entries.map { |e| e['method_key'] }).to eq(%w[card apple_pay google_pay])
    expect(entries.map { |e| e['display_name'] }).to eq(['信用卡', 'Apple Pay', 'Google Pay'])
    expect(entries.map { |e| e['frontend_kind'] }).to eq(%w[inline express express])
    expect(entries.map { |e| e['group'] }).to eq(%w[card wallet wallet])
    expect(entries.map { |e| e['position'] }).to eq([1, 2, 3])
    expect(entries.first['option_id']).to eq("#{provider.prefixed_id}:card")
    expect(entries.last['option_id']).to eq("#{provider.prefixed_id}:google_pay")
  end

  # PRD-20260918-payments-d7-payment-section-express AC-002
  it 'keeps a single implicit entry for providers that were never optionized' do
    provider = create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                                       name: 'Plain provider')

    entries = provider.payment_option_entries

    expect(entries.size).to eq(1)
    expect(entries.first['method_key']).to eq(provider.default_option_kind)
    expect(entries.first['display_name']).to eq('Plain provider')
    # 隐式入口是会话卡流（session_required → inline）→ 归卡组
    expect(entries.first['group']).to eq('card')
  end

  # PRD-20260918-payments-d7-payment-section-express AC-003
  it 'drops disabled entries' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 },
      { 'kind' => 'klarna', 'active' => false, 'position' => 2, 'frontend_kind' => 'redirect' }
    ])

    expect(provider.payment_option_entries.map { |e| e['method_key'] }).to eq(%w[card])
  end

  # PRD-20260918-payments-d7-payment-section-express AC-001（同源过滤）
  it 'filters entries by the server-side available kinds when given' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'frontend_kind' => 'express' }
    ])

    entries = provider.payment_option_entries(available_kinds: %w[card])

    expect(entries.map { |e| e['method_key'] }).to eq(%w[card])
  end

  # PRD-20260918-payments-d7-payment-section-express AC-005
  it 'reports provider-level group and position from the first effective entry' do
    provider = optionized_provider([
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 1, 'frontend_kind' => 'express' },
      { 'kind' => 'card', 'active' => true, 'position' => 2, 'frontend_kind' => 'inline' }
    ])

    expect(provider.option_group).to eq('wallet')
    expect(provider.effective_payment_option['position'].to_i).to eq(1)
  end

  # PRD-20260918-payments-d7-payment-section-express AC-006（读模型部分：形态/分组映射）
  it 'maps entry kinds to frontend kinds and groups without guessing' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 },
      { 'kind' => 'klarna', 'active' => true, 'position' => 3, 'frontend_kind' => 'redirect' },
      { 'kind' => 'bank_transfer', 'active' => true, 'position' => 4, 'frontend_kind' => 'manual' }
    ])
    manual_provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                                    name: 'Offline provider')

    expect(provider.option_frontend_kind('card')).to eq('inline')
    expect(provider.option_frontend_kind('apple_pay')).to eq('express') # 未显式配置也不猜成 inline
    expect(provider.option_frontend_kind('klarna')).to eq('redirect')
    expect(provider.option_frontend_kind('bank_transfer')).to eq('manual')
    expect(provider.option_group('card')).to eq('card')
    expect(provider.option_group('apple_pay')).to eq('wallet')
    expect(provider.option_group('klarna')).to eq('redirect')
    expect(provider.option_group('bank_transfer')).to eq('manual')
    # 非会话 provider（如 check / 银行转账）：形态与分组都是 manual
    expect(manual_provider.option_frontend_kind).to eq('manual')
    expect(manual_provider.option_group).to eq('manual')
  end
end
