# frozen_string_literal: true

require 'spec_helper'

# PRD bugfix 2026-08-26: store customers could not delete an address that was
# referenced by a transient cart/draft order's shipment (ResourceController
# pre-checked can_be_deleted? and 422'd). Now the store AddressesController
# delegates to Address#destroy, which soft-deletes (deleted_at) when the
# address is referenced and hard-deletes otherwise — matching the admin
# controller and letting customers clean up abandoned-cart addresses.
RSpec.describe 'DELETE /api/v3/store/customers/me/addresses/:id', type: :request do
  include_context 'API v3 Store authenticated'

  let(:address) { create(:address, user: user) }

  describe 'unreferenced address' do
    it 'hard-deletes the address and returns 204' do
      delete "/api/v3/store/customers/me/addresses/#{address.prefixed_id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(PallasTrade::Address.find_by(id: address.id)).to be_nil
    end
  end

  describe 'address referenced only by a draft cart shipment (abandoned cart)' do
    it 'deletes (soft-deletes) the address and returns 204' do
      cart = create(:cart, store: store, user: user, ship_address: address)
      create(:shipment, order: cart, address: address)

      delete "/api/v3/store/customers/me/addresses/#{address.prefixed_id}", headers: headers

      expect(response).to have_http_status(:no_content)
      # Soft-deleted: row preserved (cart/shipment history intact), but removed
      # from the address book (user.addresses scope filters deleted_at: nil).
      reloaded = PallasTrade::Address.find_by(id: address.id)
      expect(reloaded).to be_present
      expect(reloaded.deleted_at).to be_present
      expect(user.reload.addresses.where(id: address.id)).to be_empty
    end
  end

  describe 'address referenced by a completed order' do
    it 'soft-deletes and preserves the historical row' do
      order = create(:completed_order_with_totals, store: store, user: user)
      order.update_columns(bill_address_id: address.id)

      delete "/api/v3/store/customers/me/addresses/#{address.prefixed_id}", headers: headers

      expect(response).to have_http_status(:no_content)
      reloaded = PallasTrade::Address.find_by(id: address.id)
      expect(reloaded).to be_present
      expect(reloaded.deleted_at).to be_present
    end
  end

  describe 'authorization' do
    it 'returns 404 for another user\'s address' do
      other = create(:user)
      other_address = create(:address, user: other)

      delete "/api/v3/store/customers/me/addresses/#{other_address.prefixed_id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(PallasTrade::Address.find_by(id: other_address.id)).to be_present
    end

    it 'returns 401 without a token' do
      delete "/api/v3/store/customers/me/addresses/#{address.prefixed_id}", headers: api_key_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
