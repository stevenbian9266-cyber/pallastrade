# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，认证需求判定）
#   AC-003 ← FR-002：三模式语义（off / always / risk_based）+ 判定零写库、零 provider
#   AC-004 ← FR-002：豁免优先（低金额 TRA / 国家白名单 / 入口白名单）+ 跨币种阈值不生效
#   AC-005 ← FR-002：风险严格性优先（off + force_3ds → 仍要求认证；豁免不适用于该路径）
RSpec.describe PallasTrade::Payments::ThreeDSecure::Required do
  let(:store) do
    create(:store, code: "d15c-req-#{SecureRandom.hex(4)}", name: 'D15c Required Store',
                   default: true, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d15c-req.example.com', mail_from_address: 'no-reply@d15c-req.example.com')
  end
  let(:order) { create(:order_with_line_items, store: store, line_items_price: 100, shipment_cost: 0) }

  let(:country) do
    PallasTrade::Country.find_by(iso: 'DE') ||
      create(:country, iso: 'DE', name: 'Germany', iso_name: 'GERMANY', iso3: 'DEU', numcode: 276)
  end

  def set_policy(attributes)
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY => attributes
    ))
    store.reload
  end

  def assess!(decision)
    PallasTrade::PaymentRiskAssessment.create!(order: order, store: store, decision: decision,
                                               evaluated_at: Time.current, signals: {})
  end

  def decide(**kwargs)
    described_class.call(order: order, **kwargs).value
  end

  describe 'modes' do
    # AC-003（默认 risk_based + 无风险信号 → 不要求认证）
    it 'does not require authentication for the default policy without a risk signal' do
      outcome = decide

      expect(outcome[:required]).to be(false)
      expect(outcome[:mode]).to eq('risk_based')
      expect(outcome[:source]).to eq('none')
      expect(outcome[:reason]).to eq(described_class::REASON_NO_RISK)
      expect(outcome[:risk_action]).to be_nil
    end

    # AC-003（risk_based + force_3ds → 要求认证）
    it 'requires authentication under risk_based when the risk decision forces 3DS' do
      assess!('force_3ds')

      outcome = decide

      expect(outcome[:required]).to be(true)
      expect(outcome[:source]).to eq('risk_rule')
      expect(outcome[:risk_action]).to eq('force_3ds')
      expect(outcome[:reason]).to eq(described_class::REASON_RISK_FORCED)
    end

    # AC-003（always → 一律要求）
    it 'always requires authentication under the always mode' do
      set_policy('mode' => 'always')

      outcome = decide

      expect(outcome[:required]).to be(true)
      expect(outcome[:source]).to eq('policy')
      expect(outcome[:reason]).to eq(described_class::REASON_ALWAYS)
    end

    # AC-003（off → 不要求；且不评估豁免）
    it 'does not require authentication under the off mode without a risk signal' do
      set_policy('mode' => 'off')

      outcome = decide

      expect(outcome[:required]).to be(false)
      expect(outcome[:reason]).to eq(described_class::REASON_OFF)
      expect(outcome[:exemptions]).to eq([])
    end
  end

  describe 'exemptions' do
    # AC-004（低金额 TRA：同币种时生效）
    it 'exempts a low-amount order and records the threshold used' do
      set_policy('mode' => 'always', 'low_amount_threshold' => (order.total.to_d + 10).to_s('F'))

      outcome = decide

      expect(outcome[:required]).to be(false)
      expect(outcome[:exemptions]).to include(described_class::EXEMPTION_LOW_AMOUNT)
      expect(outcome[:reason]).to eq(described_class::REASON_EXEMPTED)
      expect(outcome[:threshold_used]).to eq(order.total.to_d + 10)
    end

    # AC-004（阈值以下不豁免：金额 >= 阈值 → 仍要求认证）
    it 'does not exempt an order at or above the threshold' do
      set_policy('mode' => 'always', 'low_amount_threshold' => '1')

      outcome = decide

      expect(outcome[:required]).to be(true)
      expect(outcome[:exemptions]).to eq([])
    end

    # AC-004（跨币种不猜：阈值不生效并如实记原因）
    it 'skips the threshold when the order currency differs from the store default' do
      set_policy('mode' => 'always', 'low_amount_threshold' => '999999')
      order.update_columns(currency: 'EUR')
      order.reload

      outcome = decide

      expect(outcome[:required]).to be(true)
      expect(outcome[:threshold_skipped]).to eq('currency_mismatch')
      expect(outcome[:threshold_used]).to be_nil
    end

    # AC-004（国家白名单）
    it 'exempts an order shipped to an allowlisted country' do
      set_policy('mode' => 'always', 'allowlisted_countries' => %w[DE])
      order.update_columns(ship_address_id: create(:address, country: country).id)
      order.reload

      outcome = decide

      expect(outcome[:exemptions]).to include(described_class::EXEMPTION_COUNTRY)
      expect(outcome[:required]).to be(false)
    end

    # AC-004（入口白名单：运营显式声明「这些入口无需挑战」）
    it 'records the option allowlist exemption' do
      set_policy('mode' => 'always', 'allowlisted_option_kinds' => %w[card])

      outcome = decide

      expect(outcome[:exemptions]).to include(described_class::EXEMPTION_OPTION)
      expect(outcome[:required]).to be(false)
    end
  end

  describe 'risk strictness' do
    # AC-005（off + force_3ds → 风险优先；且不评估豁免）
    it 'lets an explicit force_3ds rule win over the off mode and skips exemptions' do
      set_policy('mode' => 'off', 'low_amount_threshold' => '999999')
      assess!('force_3ds')

      outcome = decide

      expect(outcome[:required]).to be(true)
      expect(outcome[:policy_off_overridden_by]).to eq('risk_rule')
      expect(outcome[:exemption_policy]).to eq('skipped_mode_off')
      expect(outcome[:exemptions]).to eq([])
      expect(outcome[:reason]).to eq(described_class::REASON_OFF_OVERRIDDEN)
    end

    # AC-005（block 决策不被豁免改写 —— 豁免只放宽「是否挑战」）
    it 'does not treat a block decision as exemptable authentication' do
      set_policy('mode' => 'always', 'low_amount_threshold' => '999999')
      assess!('block')

      outcome = decide

      expect(outcome[:required]).to be(false)
      expect(outcome[:risk_action]).to eq('block')
    end

    # AC-003（显式 risk_action 参数：留痕尚未落库时也能判定）
    it 'accepts an explicit risk_action override' do
      outcome = decide(risk_action: 'force_3ds')

      expect(outcome[:required]).to be(true)
      expect(outcome[:risk_action]).to eq('force_3ds')
    end
  end

  describe 'purity' do
    # AC-003（判定只读：不写任何行）
    it 'writes nothing while deciding' do
      set_policy('mode' => 'always', 'low_amount_threshold' => '10')
      assess!('force_3ds')
      before = {
        assessments: PallasTrade::PaymentRiskAssessment.count,
        audits: PallasTrade::AuditLog.count,
        sessions: PallasTrade::PaymentSession.count,
        orders: PallasTrade::Order.count
      }

      described_class.call(order: order)

      expect(PallasTrade::PaymentRiskAssessment.count).to eq(before[:assessments])
      expect(PallasTrade::AuditLog.count).to eq(before[:audits])
      expect(PallasTrade::PaymentSession.count).to eq(before[:sessions])
      expect(PallasTrade::Order.count).to eq(before[:orders])
    end

    # NFR：判定在订单对象上复用（Resolver 逐 entry 调用不会放大查询），且**新留痕会自动失效**
    it 'reuses the decision per order object and invalidates it when a newer assessment arrives' do
      assess!('allow')
      first = described_class.for_order(order)
      expect(first[:required]).to be(false)

      assess!('force_3ds')

      expect(described_class.for_order(order)[:required]).to be(true)

      queries = 0
      counter = lambda do |*, payload|
        queries += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        3.times { described_class.for_order(order) }
      end
      # 命中缓存时只做 1 条指纹查询/次（与策略、入口数量无关）
      expect(queries).to eq(3)
    end

    # AC-003（nil 订单 → 不要求，不抛错）
    it 'returns a failure for a nil order' do
      expect(described_class.call(order: nil)).not_to be_success
      expect(described_class.for_order(nil)[:required]).to be(false)
    end
  end
end
