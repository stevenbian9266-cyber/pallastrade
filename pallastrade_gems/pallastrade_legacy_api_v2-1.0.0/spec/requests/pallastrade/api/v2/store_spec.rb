require 'spec_helper'

describe 'API v2 Store Switching spec', type: :request do
  let!(:store) { @default_store }
  let!(:another_store) { create(:store, url: 'another-store.lvh.me', name: 'Another Store') }

  let!(:product) { create(:product, stores: [store]) }
  let!(:another_product) { create(:product, stores: [another_store]) }

  context 'existing store found' do
    before do
      allow_any_instance_of(PallasTrade::Api::V2::Storefront::ProductsController).to receive(:current_store).and_return(another_store)
    end

    context 'product associated with store' do
      before { get "/api/v2/storefront/products/#{another_product.slug}" }

      it_behaves_like 'returns 200 HTTP status'
    end

    context 'product not associated with store' do
      before { get "/api/v2/storefront/products/#{product.slug}" }

      it_behaves_like 'returns 404 HTTP status'
    end
  end

  context 'non-existing store' do
    before do
      allow_any_instance_of(PallasTrade::Api::V2::Storefront::ProductsController).to receive(:current_store).and_return(store)
    end

    context 'fallbacks to the default store' do
      context 'product associated with store' do
        before { get "/api/v2/storefront/products/#{product.slug}" }

        it_behaves_like 'returns 200 HTTP status'
      end

      context 'product not associated with store' do
        before { get "/api/v2/storefront/products/#{another_product.slug}" }

        it_behaves_like 'returns 404 HTTP status'
      end
    end
  end
end
