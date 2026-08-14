# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PallasTrade::Api::Turnstile do
  describe '.configured?' do
    it 'is true when TURNSTILE_SECRET_KEY is set' do
      stub_const('ENV', ENV.to_h.merge('TURNSTILE_SECRET_KEY' => 'test-secret'))

      expect(described_class.configured?).to be(true)
    end

    it 'is false when TURNSTILE_SECRET_KEY is missing' do
      stub_const('ENV', ENV.to_h.reject { |key, _| key == 'TURNSTILE_SECRET_KEY' })

      expect(described_class.configured?).to be(false)
    end

    it 'is false when TURNSTILE_SECRET_KEY is blank' do
      stub_const('ENV', ENV.to_h.merge('TURNSTILE_SECRET_KEY' => '   '))

      expect(described_class.configured?).to be(false)
    end
  end

  describe '.verify' do
    context 'when configured' do
      before do
        stub_const('ENV', ENV.to_h.merge('TURNSTILE_SECRET_KEY' => 'test-secret'))
      end

      it 'returns true when Cloudflare reports success' do
        stub_siteverify(success: true)

        expect(described_class.verify('cf-token')).to be(true)
      end

      it 'returns false when Cloudflare reports failure' do
        stub_siteverify(success: false)

        expect(described_class.verify('cf-token')).to be(false)
      end

      it 'returns false when the token is blank' do
        expect(described_class.verify('')).to be(false)
      end

      it 'returns nil (unable to verify) when the upstream request raises' do
        allow(Net::HTTP).to receive(:new).and_raise(Timeout::Error)

        expect(described_class.verify('cf-token')).to be_nil
      end

      it 'returns nil (unable to verify) on a non-success HTTP response' do
        fake_response = double(body: { 'success' => true }.to_json)
        allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        fake_http = double(request: fake_response)
        allow(fake_http).to receive(:use_ssl=)
        allow(fake_http).to receive(:open_timeout=)
        allow(fake_http).to receive(:read_timeout=)
        allow(Net::HTTP).to receive(:new).and_return(fake_http)

        expect(described_class.verify('cf-token')).to be_nil
      end
    end

    it 'returns nil when not configured' do
      stub_const('ENV', ENV.to_h.reject { |key, _| key == 'TURNSTILE_SECRET_KEY' })

      expect(described_class.verify('cf-token')).to be_nil
    end
  end

  def stub_siteverify(success:)
    fake_response = double(body: { 'success' => success }.to_json)
    allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    fake_http = double(request: fake_response)
    allow(fake_http).to receive(:use_ssl=)
    allow(fake_http).to receive(:open_timeout=)
    allow(fake_http).to receive(:read_timeout=)
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
  end
end
