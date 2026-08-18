# frozen_string_literal: true

require 'rails_helper'

# PRD-20260815-catalog-邮件管理整合 AC-006 / AC-007
RSpec.describe PallasTrade::ContactMessage, type: :model do
  let(:store) { create(:store, code: 'ctct_model_test') }

  describe 'validations' do
    it 'is valid with a store, email and body' do
      expect(build(:contact_message, store: store)).to be_valid
    end

    it 'rejects a missing email' do
      expect(build(:contact_message, store: store, email: nil)).to be_invalid
    end

    it 'rejects a missing body' do
      expect(build(:contact_message, store: store, body: nil)).to be_invalid
    end

    it 'rejects an unknown kind' do
      expect(build(:contact_message, store: store, kind: 'bogus')).to be_invalid
    end

    it 'rejects an unknown status' do
      expect(build(:contact_message, store: store, status: 'bogus')).to be_invalid
    end
  end

  describe 'scopes' do
    it 'returns pending messages' do
      pending_msg = create(:contact_message, store: store, status: 'pending')
      create(:contact_message, store: store, status: 'resolved')
      expect(store.contact_messages.pending).to eq([pending_msg])
    end

    it 'filters by kind' do
      complaint = create(:contact_message, store: store, kind: 'complaint')
      create(:contact_message, store: store, kind: 'feedback')
      expect(store.contact_messages.by_kind('complaint')).to eq([complaint])
    end
  end
end
