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
    it 'pins the known ps collision so any new duplicate prefix fails' do
      files = Dir[Rails.root.join('pallastrade_gems/*/app/models/**/*.rb')] +
              Dir[Rails.root.join('app/models/**/*.rb')]
      # 行首声明才算（避免匹配 concern 注释里的示例）
      prefixes = files.flat_map { |file| File.read(file).scan(/^\s*has_prefix_id :([a-z0-9_]+)/).flatten }
      duplicates = prefixes.tally.select { |_prefix, count| count > 1 }.keys

      # 新增重复前缀会让 id 归属校验失效；已知残留：ps = PaymentSession / PaymentSource
      expect(duplicates).to eq(['ps'])
    end
  end
end
