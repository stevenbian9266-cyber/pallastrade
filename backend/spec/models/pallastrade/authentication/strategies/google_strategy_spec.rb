# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-other-p1-1-社交登录-google-facebook
# AC-001：GoogleStrategy 在 id_token 有效时返回 success + 用户；无效/未配置时 failure
RSpec.describe PallasTrade::Authentication::Strategies::GoogleStrategy, type: :model do
  subject(:strategy) do
    described_class.new(params: params, request_env: {}, user_class: PallasTrade.user_class)
  end

  let(:params) { { provider: 'google', id_token: 'valid-token' } }

  around do |example|
    original = ENV['GOOGLE_CLIENT_ID']
    ENV['GOOGLE_CLIENT_ID'] = 'test-client-id.apps.googleusercontent.com'
    example.run
  ensure
    ENV['GOOGLE_CLIENT_ID'] = original
  end

  # A fake validator so we don't hit Google's network in specs.
  def stub_validator(profile)
    validator = instance_double(PallasTrade::Authentication::OAuthTokenValidator, google: profile)
    allow(strategy).to receive(:validator).and_return(validator)
    validator
  end

  describe '#provider' do
    it 'is google' do
      expect(strategy.provider).to eq('google')
    end
  end

  describe '#authenticate' do
    it 'returns failure when id_token is missing' do
      result = described_class.new(params: { provider: 'google' }, request_env: {}, user_class: PallasTrade.user_class).authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('id_token is required')
    end

    it 'returns failure when GOOGLE_CLIENT_ID is not configured' do
      ENV['GOOGLE_CLIENT_ID'] = nil
      result = strategy.authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('Google sign-in is not configured')
    end

    it 'returns failure when the token is invalid' do
      stub_validator(nil)
      result = strategy.authenticate
      expect(result).not_to be_success
      expect(result.error).to eq('Invalid Google credential')
    end

    it 'creates a new user and identity for a valid token' do
      stub_validator(
        provider_uid: 'google-123',
        email: 'alice@example.com',
        first_name: 'Alice',
        last_name: 'Wang',
        email_verified: true
      )

      result = strategy.authenticate
      expect(result).to be_success

      user = result.value
      expect(user.email).to eq('alice@example.com')
      expect(user.first_name).to eq('Alice')

      identity = user.identities.find_by(provider: 'google', user_type: PallasTrade.user_class.name)
      expect(identity).to be_present
      expect(identity.uid).to eq('google-123')
    end

    it 'binds to an existing user with the same email instead of duplicating' do
      existing = create(:user, email: 'bob@example.com', first_name: 'Bob')
      stub_validator(
        provider_uid: 'google-456',
        email: 'bob@example.com',
        first_name: 'Bob',
        last_name: nil,
        email_verified: true
      )

      result = strategy.authenticate
      expect(result).to be_success
      expect(result.value.id).to eq(existing.id)

      expect(PallasTrade.user_class.count).to eq(1)
      expect(existing.identities.find_by(provider: 'google')).to be_present
    end

    it 're-authenticates an existing identity and returns its user' do
      user = create(:user, email: 'carol@example.com')
      user.identities.create!(provider: 'google', uid: 'google-789', user_type: PallasTrade.user_class.name)

      stub_validator(
        provider_uid: 'google-789',
        email: 'carol@example.com',
        first_name: 'Carol',
        last_name: nil,
        email_verified: true
      )

      result = strategy.authenticate
      expect(result).to be_success
      expect(result.value.id).to eq(user.id)
      expect(PallasTrade.user_class.count).to eq(1)
    end
  end
end
