# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，条件匹配）
#   AC-002 ← FR-002：每个受支持条件键的正/反例（含边界 = 命中）；缺失主体 → 不命中且记 skip 原因；
#                    未知键 → 不命中 + unsupported_condition（运行期不猜）
RSpec.describe PallasTrade::Risk::Rules::Condition, type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:country) do
    PallasTrade::Country.find_by(iso: 'US') ||
      create(:country, iso: 'US', name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', numcode: 840)
  end

  def build_order(email: "d15b-#{suffix}@example.com", ip: '203.0.113.7', amount: 150, currency: nil)
    order = create(:order_with_line_items, store: store, currency: currency, line_items_count: 1,
                                           line_items_price: amount, shipment_cost: 0)
    address = create(:address, country: country)
    order.update_columns(email: email, last_ip_address: ip, bill_address_id: address.id,
                         total: amount, item_total: amount, payment_total: 0)
    order.reload
  end

  def add_card_payment(order, brand: 'visa')
    method = create(:credit_card_payment_method, stores: [store])
    card = create(:credit_card, cc_type: brand, payment_method: method, fingerprint: "fp_#{suffix}")
    create(:payment, order: order, payment_method: method, source: card, amount: 10, state: 'completed')
  end

  def evaluate(order, conditions)
    described_class.call(order: order, conditions: conditions, now: Time.current).value
  end

  describe 'amount conditions' do
    # AC-002
    it 'matches amount thresholds inclusively in the store currency' do
      order = build_order(amount: 150)

      expect(evaluate(order, 'amount_gte' => 150)[:matched]).to be(true)
      expect(evaluate(order, 'amount_gte' => 150.01)[:matched]).to be(false)
      expect(evaluate(order, 'amount_lte' => 150)[:matched]).to be(true)
      expect(evaluate(order, 'amount_lte' => 149.99)[:matched]).to be(false)
    end

    # AC-002（不跨币种猜）
    #
    # ⚠️ 不要用 `create(:order_with_line_items, currency: 'EUR')` 造「币种不一致」的订单：
    #    `PallasTrade::Order` 会校验 `store.supported_currencies_list`，而该列表在**店铺有 market 时
    #    （seeds 建了默认国家 → 默认店铺自动带 market）直接来自 markets，**忽略** `supported_currencies` 列，
    #    于是本地（无 market）过、CI（有 market）报 `Validation failed: Currency is not supported by this store`。
    #    定式：先在店铺币种下建合法订单，再用 `update_columns` 改币种（绕开校验），币种取值按店铺默认币种推导。
    it 'skips amount comparisons when the order currency differs from the store default' do
      order = build_order(amount: 150)
      mismatched = store.default_currency.to_s.upcase == 'EUR' ? 'GBP' : 'EUR'
      order.update_columns(currency: mismatched)
      order.reload

      outcome = evaluate(order, 'amount_gte' => 10)

      expect(order.currency).to eq(mismatched)
      expect(outcome[:matched]).to be(false)
      expect(outcome[:skipped]).to include('currency_mismatch')
    end
  end

  describe 'currency / country / email / ip conditions' do
    # AC-002
    it 'matches currency, country, email domain and ip presence' do
      order = build_order(email: "buyer-#{suffix}@Example.COM", ip: '203.0.113.7')

      expect(evaluate(order, 'currency_in' => %w[usd])[:matched]).to be(true)
      expect(evaluate(order, 'currency_in' => %w[EUR])[:matched]).to be(false)
      expect(evaluate(order, 'country_in' => %w[us])[:matched]).to be(true)
      expect(evaluate(order, 'country_in' => %w[KP])[:matched]).to be(false)
      expect(evaluate(order, 'email_domain_in' => ['example.com'])[:matched]).to be(true)
      expect(evaluate(order, 'email_domain_in' => ['other.test'])[:matched]).to be(false)
      expect(evaluate(order, 'email_present' => true)[:matched]).to be(true)
      expect(evaluate(order, 'ip_present' => true)[:matched]).to be(true)
    end

    # AC-002（主体缺失不猜）
    it 'skips when the required subject is missing' do
      order = build_order(ip: nil)
      order.update_columns(email: nil, bill_address_id: nil)
      order.reload

      expect(evaluate(order, 'country_in' => %w[US])[:skipped]).to include('country_missing')
      expect(evaluate(order, 'email_domain_in' => ['example.com'])[:skipped]).to include('email_missing')
      expect(evaluate(order, 'email_present' => true)[:skipped]).to include('email_missing')
      expect(evaluate(order, 'ip_present' => true)[:matched]).to be(false)
    end
  end

  describe 'card brand condition' do
    # AC-002（归一：mastercard → master）
    it 'matches the normalized brand of the completed card payment' do
      order = build_order
      add_card_payment(order, brand: 'mastercard')

      expect(evaluate(order.reload, 'card_brand_in' => %w[master])[:matched]).to be(true)
      expect(evaluate(order, 'card_brand_in' => %w[visa])[:matched]).to be(false)
    end

    # AC-002
    it 'does not match when there is no completed card payment' do
      order = build_order

      expect(evaluate(order, 'card_brand_in' => %w[visa])[:matched]).to be(false)
    end
  end

  describe 'history and velocity conditions' do
    # AC-002
    it 'matches customer completed-order history' do
      user = create(:user)
      order = build_order
      order.update_columns(user_id: user.id)
      2.times do
        create(:order_with_line_items, store: store, user: user).update_columns(state: 'complete')
      end

      expect(evaluate(order.reload, 'customer_orders_gte' => 2)[:matched]).to be(true)
      expect(evaluate(order, 'customer_orders_gte' => 3)[:matched]).to be(false)
    end

    # AC-002（匿名单 → skip）
    it 'skips history checks for guest orders' do
      order = build_order
      order.update_columns(user_id: nil)

      outcome = evaluate(order.reload, 'customer_orders_gte' => 1)

      expect(outcome[:matched]).to be(false)
      expect(outcome[:skipped]).to include('customer_missing')
    end

    # AC-002（velocity：同邮箱或同 IP 在窗口内的订单数；含当前订单）
    it 'counts orders in the window by email or ip' do
      email = "velocity-#{suffix}@example.com"
      order = build_order(email: email, ip: '203.0.113.8')
      # 同 IP 不同邮箱、窗口内
      build_order(email: "other-#{suffix}@example.com", ip: '203.0.113.8')
      # 同邮箱不同 IP、窗口外（3 小时前）
      build_order(email: email, ip: nil).update_columns(created_at: 3.hours.ago)

      in_window = evaluate(order.reload, 'velocity_count_gte' => 2, 'velocity_window_minutes' => 60)
      expect(in_window[:matched]).to be(true)

      out_of_window = evaluate(order, 'velocity_count_gte' => 3, 'velocity_window_minutes' => 60)
      expect(out_of_window[:matched]).to be(false)

      wide_window = evaluate(order, 'velocity_count_gte' => 3, 'velocity_window_minutes' => 10_080)
      expect(wide_window[:matched]).to be(true)
    end

    # AC-002
    it 'skips velocity when neither email nor ip is present' do
      order = build_order(ip: nil)
      order.update_columns(email: nil)

      outcome = evaluate(order.reload, 'velocity_count_gte' => 1)

      expect(outcome[:matched]).to be(false)
      expect(outcome[:skipped]).to include('velocity_subject_missing')
    end
  end

  describe 'combination and unknown keys' do
    # AC-002（AND 语义）
    it 'requires every condition to match' do
      order = build_order(amount: 150)

      expect(evaluate(order, 'amount_gte' => 100, 'currency_in' => %w[USD])[:matched]).to be(true)
      expect(evaluate(order, 'amount_gte' => 100, 'currency_in' => %w[EUR])[:matched]).to be(false)
    end

    # AC-002（未知键不猜）
    it 'never matches an unsupported key and records it as skipped' do
      order = build_order
      outcome = evaluate(order, 'bin_in' => %w[411111])

      expect(outcome[:matched]).to be(false)
      expect(outcome[:skipped]).to include('unsupported_condition:bin_in')
    end

    # AC-002（事实留痕：可解释）
    it 'reports the observed facts for the assessment trail' do
      order = build_order(amount: 150)
      outcome = evaluate(order, 'amount_gte' => 100)

      expect(outcome[:observed]).to include('amount' => '150.0', 'currency' => 'USD', 'country' => 'US',
                                            'email_present' => true, 'ip_present' => true)
    end
  end
end
