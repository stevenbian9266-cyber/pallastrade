# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'POST /api/v3/store/customers (Turnstile human verification)', type: :request do
  include_context 'API v3 Store guest'

  let(:valid_params) do
    {
      email: 'new.customer@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'New',
      last_name: 'Customer'
    }
  end

  context 'when TURNSTILE_SECRET_KEY is not configured' do
    it 'creates the customer without Turnstile verification (graceful degradation)' do
      allow(PallasTrade::Api::Turnstile).to receive(:configured?).and_return(false)

      post '/api/v3/store/customers', params: valid_params, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:user][:email]).to eq('new.customer@example.com')
    end
  end

  context 'when TURNSTILE_SECRET_KEY is configured' do
    before do
      allow(PallasTrade::Api::Turnstile).to receive(:configured?).and_return(true)
    end

    it 'creates the customer when verification succeeds' do
      allow(PallasTrade::Api::Turnstile).to receive(:verify).and_return(true)

      post '/api/v3/store/customers', params: valid_params, headers: headers

      expect(response).to have_http_status(:created)
    end

    it 'rejects registration when verification fails' do
      allow(PallasTrade::Api::Turnstile).to receive(:verify).and_return(false)

      post '/api/v3/store/customers', params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('turnstile_verification_failed')
    end

    it 'creates the customer when verification is unreachable (degrade open with warning)' do
      allow(PallasTrade::Api::Turnstile).to receive(:verify).and_return(nil)
      allow(Rails.logger).to receive(:warn)

      post '/api/v3/store/customers', params: valid_params, headers: headers

      expect(response).to have_http_status(:created)
      expect(Rails.logger).to have_received(:warn).with(/Turnstile.*unreachable/)
    end

    it 'passes the turnstile token and client IP to the verifier' do
      allow(PallasTrade::Api::Turnstile).to receive(:verify).and_return(true)

      post '/api/v3/store/customers',
        params: valid_params.merge(turnstile_token: 'cf-token-123'),
        headers: headers

      expect(PallasTrade::Api::Turnstile).to have_received(:verify).with(
        'cf-token-123', remote_ip: anything
      )
    end
  end
end
