# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-other-prefixedid-ownership-validation（research §9.1 P0-f）：
# 前缀是资源类型标识 —— 跨前缀 id 不得解析为另一资源的整型 PK（防串单）。
RSpec.describe PallasTrade::PrefixedId do
  let(:store) { @default_store || create(:store, default: true) }
  let(:product) { create(:product_in_stock, store: store) }

  # 用同一 sqid 载荷换一个前缀：解码出的整数确实指向该记录，但前缀属于别的资源。
  def re_prefix(record, prefix)
    "#{prefix}_#{record.prefixed_id.split('_', 2).last}"
  end

  describe 'ownership validation' do
    # PRD-20260914-other-prefixedid-ownership-validation AC-001
    it 'resolves a record with its own prefix' do
      expect(PallasTrade::Product.find_by_prefix_id!(product.prefixed_id)).to eq(product)
      expect(PallasTrade::Product.find_by_prefix_id(product.prefixed_id)).to eq(product)
    end

    # PRD-20260914-other-prefixedid-ownership-validation AC-002
    it 'refuses a foreign prefix instead of resolving another resource' do
      foreign = re_prefix(product, 'or')

      # 证明修复前会串单：该字符串解码出的整数正是此商品的 PK
      expect(PallasTrade::PrefixedId.decode_prefixed_id(foreign)).to eq(product.id)

      expect { PallasTrade::Product.find_by_prefix_id!(foreign) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(PallasTrade::Product.find_by_prefix_id(foreign)).to be_nil
    end

    # PRD-20260914-other-prefixedid-ownership-validation AC-003
    it 'returns an empty set for foreign-prefix filters instead of raising' do
      decoded = PallasTrade::Product.decode_owned_prefixed_id(re_prefix(product, 'variant'))

      expect(decoded).to be_nil
      expect(PallasTrade::Product.where(id: decoded)).to be_empty
    end
  end

  describe 'Order.find_by_param' do
    let(:order) { create(:order_with_line_items, store: store, line_items_count: 1) }

    # PRD-20260914-other-prefixedid-ownership-validation AC-004
    it 'does not resolve a foreign prefix as an order' do
      expect(PallasTrade::Order.find_by_param(re_prefix(product, 'prod'))).to be_nil
    end

    # PRD-20260914-other-prefixedid-ownership-validation AC-005
    it 'still resolves its own prefix and the legacy order number' do
      expect(PallasTrade::Order.find_by_param(order.prefixed_id)).to eq(order)
      expect(PallasTrade::Order.find_by_param(order.number)).to eq(order)
    end
  end

  describe 'prefix registry' do
    # PRD-20260914-other-prefixedid-ownership-validation AC-006
    # PRD-20260914-other-paymentsource-prefix-disambiguation AC-001
    it 'keeps every declared prefix globally unique' do
      files = Dir[Rails.root.join('pallastrade_gems/*/app/models/**/*.rb')] +
              Dir[Rails.root.join('app/models/**/*.rb')]
      # 行首声明才算（避免匹配 concern 注释里的示例）
      prefixes = files.flat_map { |file| File.read(file).scan(/^\s*has_prefix_id :([a-z0-9_]+)/).flatten }
      duplicates = prefixes.tally.select { |_prefix, count| count > 1 }.keys

      expect(duplicates).to eq([])
    end
  end

  # PRD-20260914-other-paymentsource-prefix-disambiguation（AC-002/AC-003）：
  # PaymentSession(`ps_`) 与 PaymentSource(`src_`) 曾共用 `ps` 前缀 → 二者 id 无法区分，
  # 依赖前缀判类型的代码（如 PaymentSessionReservationSubscriber）会串单。
  describe 'resource disambiguation' do
    it 'declares distinct prefixes for PaymentSession and PaymentSource' do
      expect(PallasTrade::PaymentSession._prefix_id_prefix).to eq('ps')
      expect(PallasTrade::PaymentSource._prefix_id_prefix).to eq('src')
    end

    it 'never resolves one resource through the other resource id' do
      source = PallasTrade::PaymentSource.new
      source.id = 4242
      expect(source.prefixed_id).to start_with('src_')

      # 解码证明：同 payload 换回旧的 ps_ 前缀，旧实现对同 PK 的 PaymentSession 会命中
      payload = source.prefixed_id.split('_', 2).last
      expect(PallasTrade::PaymentSession.decode_prefixed_id("ps_#{payload}")).to eq(4242)

      expect(PallasTrade::PaymentSession.find_by_prefix_id(source.prefixed_id)).to be_nil

      session = PallasTrade::PaymentSession.new
      session.id = 4242
      expect(session.prefixed_id).to start_with('ps_')
      expect(PallasTrade::PaymentSource.find_by_prefix_id(session.prefixed_id)).to be_nil
    end

    # PRD-20260914-other-paymentsource-prefix-disambiguation AC-004
    it 'emits the src_ prefix on the API surface (payment setup session)' do
      source = PallasTrade::PaymentSource.new
      source.id = 7
      setup_session = PallasTrade::PaymentSetupSession.new
      setup_session.payment_source = source

      payload = PallasTrade.api.payment_setup_session_serializer.new(setup_session).to_h

      # serializer payload 使用字符串键（API 信封口径）
      expect(payload['payment_source_id']).to eq(source.prefixed_id)
      expect(payload['payment_source_id']).to start_with('src_')
    end
  end
end
