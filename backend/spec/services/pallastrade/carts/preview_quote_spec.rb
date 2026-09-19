# frozen_string_literal: true

require 'spec_helper'

# PRD-20260919-shipping-checkout-quote-preview AC-002 ~ AC-005（服务端只读预览报价）。
#
# 断言三件事：
#   1. 金额与**同参数** `Carts::Submit`（prepare 权威报价）逐字段一致（同源管线）；
#   2. dry-run 零副作用（无 Order/Event/Job/PaymentSession，车仍 active，礼品卡余额不变）；
#   3. 默认选中由服务端决定（费率成本最低），州级 zone 方式缺州时带 `address_required`。
RSpec.describe PallasTrade::Carts::PreviewQuote, type: :service do
  let(:store) { @default_store }
  let(:product) { create(:product_in_stock, store: store) }
  let(:variant) { product.master }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }
  let(:country) { PallasTrade::Country.find_by(iso: 'US') || create(:country, iso: 'US', name: 'United States') }
  let(:shipping_category) { create(:shipping_category) }

  before do
    variant.set_price('USD', 19.99) unless variant.amount_in('USD')
    product.update!(shipping_category_id: shipping_category.id)
    cart.update!(email: 'buyer@example.com')
  end

  def add_item(quantity: 2)
    PallasTrade::Carts::UpsertItems.call(
      cart: cart,
      items: [{ variant_id: variant.prefixed_id, quantity: quantity, selected: true }]
    )
  end

  # 表单态地址参数（与已落库地址同值，用于「同参数」对比）
  def address_params(address)
    {
      first_name: address.firstname,
      last_name: address.lastname,
      address1: address.address1,
      city: address.city,
      postal_code: address.zipcode,
      country_iso: address.country_iso,
      state_abbr: address.state&.abbr
    }
  end

  # 预览必须**总是**成功（失败即预算不可用 → 前台回落短标签）；失败时给出真实原因。
  def preview_for(**args)
    result = described_class.call(cart: cart, **args)
    raise "preview failed: #{result.error}" unless result.success?

    result.value
  end

  # 国家级 zone（无条件限制）→ 无地址也可计价
  def create_country_zone_method(cost: 5.0, name: 'Standard')
    zone = create(:zone)
    zone.members << PallasTrade::ZoneMember.create(zoneable: country)
    create(:shipping_method,
           name: name,
           zones: [zone],
           shipping_categories: [shipping_category],
           calculator: create(:shipping_calculator, preferred_amount: cost))
  end

  # 州级 zone（缺州无法命中）→ 必须返回 address_required 而不是 0/隐藏
  def create_state_zone_method(cost: 12.0, name: 'State only', abbr: 'CA')
    state = PallasTrade::State.find_by(country: country, abbr: abbr) ||
            create(:state, country: country, abbr: abbr, name: 'California')
    zone = create(:zone)
    zone.members << PallasTrade::ZoneMember.create(zoneable: state)
    create(:shipping_method,
           name: name,
           zones: [zone],
           shipping_categories: [shipping_category],
           calculator: create(:shipping_calculator, preferred_amount: cost))
  end

  describe '#call' do
    it 'returns amounts identical to a same-parameter submit (single pipeline)' do
      create_country_zone_method(cost: 7.5)
      address = create(:address, user: nil)
      cart.update!(shipping_address: address)
      add_item

      preview = preview_for(shipping_address: address_params(address))
      prepare = PallasTrade::Carts::Submit.call(cart: cart).value

      expect(preview['delivery_total']).to eq(prepare.delivery_total.to_s)
      expect(preview['tax_total']).to eq(prepare.tax_total.to_s)
      expect(preview['display_amount_due']).to eq(prepare.display_combined_amount_due.to_s)
      expect(preview['currency']).to eq(prepare.currency)
      expect(preview['estimated']).to be true
      expect(preview['provisional_country']).to eq(address.country_iso)
    end

    it 'writes nothing: no order, no event, no payment session; cart stays active' do
      create_country_zone_method(cost: 5.0)
      gift_card = create(:gift_card, store: store, amount: 10.00)
      cart.update!(private_metadata: { 'gift_card_code' => gift_card.code.downcase })
      add_item

      orders_before = PallasTrade::Order.where(cart_id: cart.id).count
      sessions_before = PallasTrade::PaymentSession.count

      expect(PallasTrade::Events).not_to receive(:publish)
      result = described_class.call(cart: cart, country: 'US')

      expect(result).to be_success
      expect(PallasTrade::Order.where(cart_id: cart.id).count).to eq(orders_before)
      expect(PallasTrade::PaymentSession.count).to eq(sessions_before)
      cart.reload
      expect(cart.status).to eq('active')
      expect(cart.converted_at).to be_nil
      expect(cart.shipping_address).to be_nil # 预览地址不落库
      expect(gift_card.reload.amount_used.to_d).to eq(0.to_d)
    end

    it 'selects the cheapest priced method as the server-side default' do
      create_country_zone_method(cost: 9.0, name: 'Expensive')
      create_country_zone_method(cost: 3.0, name: 'Cheap')
      add_item

      preview = preview_for(country: 'US')
      cheapest = preview['methods'].min_by { |m| m['cost'].to_d }

      expect(preview['selected_method_id']).to eq(cheapest['id'])
      expect(preview['selected_method_id']).to be_present
      expect(preview['methods'].find { |m| m['id'] == preview['selected_method_id'] }['cost']).to eq('3.0')
    end

    it 'honours an explicitly requested method when it is still priced' do
      create_country_zone_method(cost: 9.0, name: 'Expensive')
      expensive = create_country_zone_method(cost: 3.0, name: 'Cheap')
      add_item

      preview = preview_for(country: 'US', shipping_method_id: expensive.prefixed_id)

      expect(preview['selected_method_id']).to eq(expensive.prefixed_id)
    end

    it 'marks state-level methods as address_required instead of pricing them at zero' do
      create_state_zone_method(cost: 12.0, name: 'CA only')
      add_item

      preview = preview_for(country: 'US')
      state_row = preview['methods'].find { |m| m['name'] == 'CA only' }

      expect(state_row).to be_present
      expect(state_row['cost']).to be_nil
      expect(state_row['reason']).to eq('address_required')
      expect(preview['address_complete']).to be false
      # 金额未知 → 一律 nil（前台回落「提交时计算」），绝不编 0
      expect(preview['delivery_total']).to be_nil
      expect(preview['display_amount_due']).to be_nil
      expect(preview['unavailable_reason']).to eq('delivery_unavailable')
    end

    it 'prices the state-level method once the state is supplied (no persistence)' do
      create_state_zone_method(cost: 12.0, name: 'CA only')
      add_item

      preview = preview_for(
        shipping_address: { country_iso: 'US', state_abbr: 'CA', city: 'Los Angeles', postal_code: '90001' }
      )
      state_row = preview['methods'].find { |m| m['name'] == 'CA only' }

      expect(state_row['cost']).to be_present
      expect(state_row['reason']).to be_nil
      expect(preview['address_complete']).to be true
      expect(cart.reload.shipping_address).to be_nil
    end

    it 'falls back to the tax default zone without any address (never blank when a rate exists)' do
      create_country_zone_method(cost: 5.0)
      add_item

      preview = preview_for(country: 'US')

      # 无地址：运费来自国家级临时地址，税费来自 Order#tax_zone 的默认税区
      expect(preview['delivery_total'].to_d).to be > 0
      expect(preview['tax_total']).not_to be_nil
    end

    it 'returns an empty method list with no selected method when nothing is shippable' do
      add_item

      preview = preview_for(country: 'US')

      expect(preview['methods']).to eq([])
      expect(preview['selected_method_id']).to be_nil
      expect(preview['delivery_total']).to be_nil
    end
  end
end
