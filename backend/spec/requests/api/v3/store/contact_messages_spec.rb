# frozen_string_literal: true

require 'spec_helper'

# PRD-20260815-catalog-邮件管理整合 AC-007
RSpec.describe 'POST /api/v3/store/contact_messages', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }
  let(:path) { '/api/v3/store/contact_messages' }

  describe 'POST' do
    it 'creates a feedback message' do
      post path, params: {
        contact_message: { kind: 'feedback', name: 'Test', email: 'a@b.com', subject: 'Nice', body: 'Love it!' }
      }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:kind]).to eq('feedback')
      expect(json_response[:email]).to eq('a@b.com')
      expect(json_response[:body]).to eq('Love it!')
      expect(json_response[:status]).to eq('pending')
    end

    it 'creates a complaint' do
      post path, params: {
        contact_message: { kind: 'complaint', email: 'c@d.com', body: 'Broken item' }
      }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:kind]).to eq('complaint')
      expect(PallasTrade::ContactMessage.for_store(store).count).to eq(1)
    end

    it 'rejects a missing email' do
      post path, params: {
        contact_message: { kind: 'feedback', body: 'Hi' }
      }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects a missing body' do
      post path, params: {
        contact_message: { kind: 'feedback', email: 'a@b.com' }
      }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an unknown kind' do
      post path, params: {
        contact_message: { kind: 'bogus', email: 'a@b.com', body: 'Hi' }
      }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
