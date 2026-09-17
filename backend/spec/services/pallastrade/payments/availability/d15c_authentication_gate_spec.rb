# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，入口闸门）
#   AC-008 ← FR-004：要求认证时，只有声明可强制认证的入口可用；`evaluate` 给 three_d_secure 原因；
#                    前台列表与 Start 同源（同一份 Resolver）
#   AC-010 ← FR-004：不要求认证时，可用入口与变更前逐项相同（零回归）
#   AC-015 ← NFR：判定/闸门的查询数不随入口数增长
#
# 用**真实 Stripe 目录**（`card` = supported；`apple_pay` / `google_pay` = unsupported），
# 且每个 example 用**独立门店**（`@default_store` 是跨 example 共享对象，
# 在其上写 `private_metadata` 会泄漏到其它用例 —— D15c 实测）。
RSpec.describe PallasTrade::Payments::Availability::Resolver, 'D15c authentication gate' do
  let(:store) do
    create(:store, code: "d15c-gate-#{SecureRandom.hex(4)}", name: 'D15c Gate Store',
                   default: false, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d15c-gate.example.com', mail_from_address: 'no-reply@d15c-gate.example.com')
  end
  let(:order) { create(:order_with_line_items, store: store, line_items_price: 100, shipment_cost: 0) }

  def stripe_provider(kinds: %w[card apple_pay], name_suffix: SecureRandom.hex(3))
    create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                            name: "D15c #{name_suffix}",
                            metadata: {
                              'optionized' => true,
                              'options' => kinds.each_with_index.map do |kind, index|
                                { 'kind' => kind, 'active' => true, 'position' => index + 1 }
                              end
                            })
  end

  def set_policy(attributes)
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY => attributes
    ))
    store.reload
  end

  # 认证需求来自「策略 + 最新留痕」；策略变更后让订单侧关联与判定缓存失效
  # （真实请求里每单一个新对象，测试里需要显式刷新）
  def require_authentication!
    set_policy('mode' => 'always')
    order.reload
    PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)
  end

  # AC-010（零回归：不要求认证时入口与今天逐项相同）
  it 'keeps every configured entry available when authentication is not required' do
    provider = stripe_provider

    expect(PallasTrade::Payments::ThreeDSecure::Required.for_order(order)[:required]).to be(false)
    expect(described_class.available_option_kinds(order: order, payment_method: provider)).
      to eq(%w[card apple_pay])
  end

  # AC-008（要求认证 → 只剩可强制认证的入口）
  it 'drops entries that cannot force authentication' do
    provider = stripe_provider
    require_authentication!

    expect(described_class.available_option_kinds(order: order, payment_method: provider)).to eq(%w[card])
  end

  # AC-008（原因可读）
  it 'reports three_d_secure / authentication_required as the exclusion reason' do
    provider = stripe_provider
    require_authentication!

    evaluated = described_class.evaluate(order: order, payment_method: provider)
    apple_pay = evaluated.find { |entry| entry['kind'] == 'apple_pay' }
    card = evaluated.find { |entry| entry['kind'] == 'card' }

    expect(apple_pay['allowed']).to be(false)
    expect(apple_pay['reasons']).to include({ 'dimension' => 'three_d_secure',
                                              'reason' => 'authentication_required' })
    expect(card['allowed']).to be(true)
    expect(card['reasons']).not_to include({ 'dimension' => 'three_d_secure',
                                             'reason' => 'authentication_required' })
  end

  # AC-008（provider 级：只剩钱包的 provider 整条从前台列表消失）
  it 'removes a provider whose entries are all incapable of authentication' do
    wallet_only = stripe_provider(kinds: %w[apple_pay google_pay])
    card_provider = stripe_provider(kinds: %w[card])
    require_authentication!

    ids = described_class.providers(order: order.reload, scope: :frontend).map(&:id)

    expect(ids).to include(card_provider.id)
    expect(ids).not_to include(wallet_only.id)
  end

  # AC-008（未声明能力 = 不支持，不猜）
  it 'treats an entry without a declared capability as unsupported' do
    provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                             name: "D15c custom #{SecureRandom.hex(3)}",
                                             metadata: {
                                               'optionized' => true,
                                               'options' => [{ 'kind' => 'check', 'active' => true,
                                                               'position' => 1 }]
                                             })
    require_authentication!

    expect(PallasTrade::Payments::ThreeDSecure::ProviderHint.option_supported?(provider, 'check')).to be(false)
    expect(described_class.available_option_kinds(order: order, payment_method: provider)).to eq([])
    expect(described_class.evaluate(order: order, payment_method: provider).first['allowed']).to be(false)
  end

  # AC-008（显式 context 生效：Context 承载订单级认证需求）
  it 'honours an explicitly passed context' do
    provider = stripe_provider
    context = PallasTrade::Payments::Availability::Context.new(currency: 'USD', authentication_required: true)

    expect(described_class.available_option_kinds(order: order, payment_method: provider,
                                                  context: context)).to eq(%w[card])
    expect(described_class.evaluate(order: order, payment_method: provider, context: context).
      find { |entry| entry['kind'] == 'apple_pay' }['allowed']).to be(false)
  end

  # AC-015（查询数不随入口数增长）
  it 'does not grow the query count with the number of entries' do
    require_authentication!
    small = stripe_provider(kinds: %w[card apple_pay])
    large = stripe_provider(kinds: %w[card apple_pay google_pay])

    count_for = lambda do |provider|
      queries = 0
      counter = lambda do |*, payload|
        queries += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      order.reload
      PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        described_class.available_option_kinds(order: order, payment_method: provider)
      end
      queries
    end

    expect(count_for.call(large)).to eq(count_for.call(small))
  end
end
