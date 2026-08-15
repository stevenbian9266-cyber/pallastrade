# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PallasTrade::ProductUrlChange do
  # Explicit code: avoid collision with leftover rows in the shared test DB.
  let(:store) { create(:store, code: 'url_change_test_store') }

  it 'reports products whose slug changed (old vs current)' do
    product = create(:product, store: store, name: 'Old Shaver')
    product.update!(slug: 'new-shaver')

    entry = described_class.call(store).find { |r| r[:product] == product }

    expect(entry).not_to be_nil
    expect(entry[:old_slug]).to eq('old-shaver')
    expect(entry[:current_slug]).to eq('new-shaver')
    expect(entry[:from_path]).to eq('/products/old-shaver')
    expect(entry[:to_path]).to eq('/products/new-shaver')
    expect(entry[:handled]).to be(false)
  end

  it 'excludes products whose slug never changed' do
    product = create(:product, store: store, name: 'Never Changed')

    result = described_class.call(store)
    expect(result.find { |r| r[:product] == product }).to be_nil
  end

  it 'marks handled when a redirect for the old URL already exists' do
    product = create(:product, store: store, name: 'Old Shaver')
    product.update!(slug: 'new-shaver')
    create(:redirect, store: store, from_path: '/products/old-shaver', to_path: '/products/new-shaver')

    entry = described_class.call(store).find { |r| r[:product] == product }
    expect(entry).not_to be_nil
    expect(entry[:handled]).to be(true)
  end

  it 'does not leak products from other stores' do
    other_store = create(:store, code: 'url_change_other_store')
    other_product = create(:product, store: other_store, name: 'Other Shaver')
    other_product.update!(slug: 'other-new-shaver')

    result = described_class.call(store)
    expect(result.find { |r| r[:product] == other_product }).to be_nil
  end
end
