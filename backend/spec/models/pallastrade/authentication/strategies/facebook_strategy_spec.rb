# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-other-p1-1-社交登录-google-facebook
# AC-002：FacebookStrategy 在 access_token 有效时返回 success + 用户；无效/未配置时 failure
RSpec.describe PallasTrade::Authentication::Strategies::FacebookStrategy, type: :model do
  subject(:strategy) do
    described_class.new(params: params, request_env: {}, user_class: PallasTrade.user_class)
  end

  let(:params) { { provider: 'facebook', access_token: 'user-token' } }

  around do |example|
    original_id = ENV['FACEBOOK_APP_ID']
    original_secret = ENV['FACEBOOK_APP_SECRET']
    ENV['FACEBOOK_APP_ID'] = '123456'
    ENV['FACEBOOK_APP_SECRET'] = 'app-secret'
    example.run
  ensure
    ENV['FACEBOOK_APP_ID'] = original_id
    ENV['FACEBOOK_APP_SECRET'] = original_secret
  end

  def stub_validator(profile)
    validator = instance_double(PallasTrade::Authentication::OAuthTokenValidator, facebook: profile)
    allow(strategy).to receive(:validator).and_return(validator)
    validator
  end

  describe '#provider' do
    it 'is facebook' do
      expect(strategy.provider).to eq('facebook')
    end
  end

  describe '#authenticate' do
    it 'returns failure when access_token is missing' do
      result = described_class.new(params: { provider: 'facebook' }, request_env: {}, user_class: PallasTrade.user_class).authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('access_token is required')
    end

    it 'returns failure when Facebook app credentials are not configured' do
      ENV['FACEBOOK_APP_ID'] = nil
      result = strategy.authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('Facebook sign-in is not configured')
    end

    it 'returns failure when the token is invalid' do
      stub_validator(nil)
      result = strategy.authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('Invalid Facebook credential')
    end

    it 'creates a new user and identity for a valid token' do
      stub_validator(
        provider_uid: 'fb-100',
        email: 'dave@example.com',
        first_name: 'Dave',
        last_name: 'Li',
        email_verified: true
      )

      result = strategy.authenticate
      expect(result).to be_success

      user = result.value
      expect(user.email).to eq('dave@example.com')
      expect(user.last_name).to eq('Li')

      identity = user.identities.find_by(provider: 'facebook', user_type: PallasTrade.user_class.name)
      expect(identity).to be_present
      expect(identity.uid).to eq('fb-100')
    end

    it 'binds to an existing user with the same email instead of duplicating' do
      existing = create(:user, email: 'eve@example.com')
      stub_validator(
        provider_uid: 'fb-200',
        email: 'eve@example.com',
        first_name: 'Eve',
        last_name: nil,
        email_verified: true
      )

      result = strategy.authenticate
      expect(result).to be_success
      expect(result.value.id).to eq(existing.id)
      expect(PallasTrade.user_class.count).to eq(1)
      expect(existing.identities.find_by(provider: 'facebook')).to be_present
    end
  end
end
