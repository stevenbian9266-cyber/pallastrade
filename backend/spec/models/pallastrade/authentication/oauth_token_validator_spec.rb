# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-other-p1-1-社交登录-google-facebook
# AC-001/AC-002：OAuthTokenValidator 的 Google/Facebook token 验证逻辑
RSpec.describe PallasTrade::Authentication::OAuthTokenValidator, type: :model do
  let(:validator) do
    described_class.new(
      google_client_id: 'test-client.apps.googleusercontent.com',
      facebook_app_id: '123456',
      facebook_app_secret: 'secret'
    )
  end

  # Stub the private HTTP layer so specs never hit the network.
  def stub_get_json(response)
    allow(validator).to receive(:get_json) { |_url, **query| response.call(query) }
  end

  describe '#google' do
    it 'returns nil when id_token is blank' do
      expect(validator.google(nil)).to be_nil
      expect(validator.google('')).to be_nil
    end

    it 'returns nil when the audience does not match the client id' do
      stub_get_json(->(_q) { { 'aud' => 'attacker.apps.googleusercontent.com', 'email' => 'a@b.com' } })
      expect(validator.google('token')).to be_nil
    end

    it 'returns nil when the token is expired' do
      stub_get_json(->(_q) { { 'aud' => 'test-client.apps.googleusercontent.com', 'email' => 'a@b.com', 'exp' => Time.now.to_i - 100 } })
      expect(validator.google('token')).to be_nil
    end

    it 'returns nil when no email is present' do
      stub_get_json(->(_q) { { 'aud' => 'test-client.apps.googleusercontent.com' } })
      expect(validator.google('token')).to be_nil
    end

    it 'returns normalized profile claims for a valid token' do
      stub_get_json(->(_q) {
        { 'aud' => 'test-client.apps.googleusercontent.com', 'sub' => 'g-1', 'email' => 'a@b.com', 'given_name' => 'Ann', 'family_name' => 'B', 'email_verified' => 'true', 'exp' => Time.now.to_i + 1000 }
      })
      profile = validator.google('token')
      expect(profile[:provider_uid]).to eq('g-1')
      expect(profile[:email]).to eq('a@b.com')
      expect(profile[:first_name]).to eq('Ann')
      expect(profile[:last_name]).to eq('B')
      expect(profile[:email_verified]).to eq(true)
    end
  end

  describe '#facebook' do
    it 'returns nil when access_token is blank' do
      expect(validator.facebook(nil)).to be_nil
      expect(validator.facebook('')).to be_nil
    end

    it 'returns nil when the debug token is invalid' do
      stub_get_json(->(q) {
        return { 'data' => { 'is_valid' => false, 'app_id' => '123456', 'type' => 'USER' } } if q[:input_token]
      })
      expect(validator.facebook('token')).to be_nil
    end

    it 'returns nil when the token belongs to another app' do
      stub_get_json(->(q) {
        return { 'data' => { 'is_valid' => true, 'app_id' => '999999', 'type' => 'USER' } } if q[:input_token]
      })
      expect(validator.facebook('token')).to be_nil
    end

    it 'returns normalized profile claims for a valid token' do
      stub_get_json(->(q) {
        if q[:input_token]
          { 'data' => { 'is_valid' => true, 'app_id' => '123456', 'type' => 'USER' } }
        else
          { 'id' => 'fb-1', 'name' => 'Carl Chen', 'email' => 'c@d.com' }
        end
      })
      profile = validator.facebook('token')
      expect(profile[:provider_uid]).to eq('fb-1')
      expect(profile[:email]).to eq('c@d.com')
      expect(profile[:first_name]).to eq('Carl')
      expect(profile[:last_name]).to eq('Chen')
      expect(profile[:email_verified]).to eq(true)
    end
  end
end
