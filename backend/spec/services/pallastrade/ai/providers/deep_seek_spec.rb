# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-api-deepseek-structured-output — DeepSeek provider adapter.
#
# Regression cover for the dev outage where every schema-bearing capability
# failed with HTTP 400 because the adapter sent a `response_format` type
# DeepSeek does not implement (`json_schema`), and where `system_instructions`
# were dropped from the outgoing payload altogether.
#
# The specs stub the Faraday connection: they assert the outgoing request body
# without touching the network, and without depending on the encrypted
# credential path (CI does not inject ACTIVE_RECORD_ENCRYPTION_*).
RSpec.describe PallasTrade::AI::Providers::DeepSeek, type: :service do
  subject(:adapter) { described_class.new }

  let(:integration) { double('integration') }
  let(:captured) { {} }

  let(:connection) do
    captured_body = captured

    double('Faraday::Connection').tap do |conn|
      allow(conn).to receive(:post) do |path, &block|
        request = double('Faraday::Request')
        allow(request).to receive(:headers).and_return({})
        allow(request).to receive(:body=) do |value|
          captured_body[:path] = path
          captured_body[:body] = JSON.parse(value)
        end
        block.call(request)

        double('Faraday::Response', body: { 'choices' => [{ 'message' => { 'content' => '{}' } }] }.to_json)
      end
    end
  end

  before do
    allow(adapter).to receive(:validate_configuration!)
    allow(adapter).to receive(:build_connection).and_return(connection)
    allow(integration).to receive(:decrypted_api_key).and_return('sk-test')
  end

  def request_with(messages:, system_instructions: nil, response_schema: nil)
    PallasTrade::AI::Providers::Request.new(
      messages: messages,
      model: 'deepseek-flash',
      system_instructions: system_instructions,
      response_schema: response_schema,
      parameters: {}
    )
  end

  def generated_body(request)
    adapter.generate(integration, request)
    captured[:body]
  end

  let(:schema) do
    {
      type: 'object',
      properties: { meta_title: { type: 'string' } },
      required: %w[meta_title]
    }
  end

  let(:plain_request) do
    request_with(messages: [{ role: 'user', content: 'Write a description.' }])
  end

  describe '#generate structured output' do
    it 'asks for a json_object, never the unsupported json_schema (# PRD-20260918-api-deepseek-structured-output AC-001)' do
      body = generated_body(request_with(messages: [{ role: 'user', content: 'Write SEO copy.' }], response_schema: schema))

      expect(body['response_format']).to eq('type' => 'json_object')
      expect(body['response_format']).not_to have_key('json_schema')
    end

    it 'carries the schema and the literal word json in the prompt (# PRD-20260918-api-deepseek-structured-output AC-002)' do
      body = generated_body(request_with(messages: [{ role: 'user', content: 'Write SEO copy.' }], response_schema: schema))

      system_message = body['messages'].first
      expect(system_message['role']).to eq('system')
      expect(system_message['content']).to include('json')
      expect(system_message['content']).to include('meta_title')
    end

    it 'keeps the plain-text path free of response_format (# PRD-20260918-api-deepseek-structured-output AC-003)' do
      expect(generated_body(plain_request)).not_to have_key('response_format')
    end
  end

  describe '#generate system instructions' do
    it 'sends system instructions as the first message (# PRD-20260918-api-deepseek-structured-output AC-004)' do
      request = request_with(
        messages: [{ role: 'user', content: 'Write a description.' }],
        system_instructions: 'Never invent specifications.'
      )

      messages = generated_body(request)['messages']

      expect(messages.first).to eq('role' => 'system', 'content' => 'Never invent specifications.')
      expect(messages.last).to eq('role' => 'user', 'content' => 'Write a description.')
      expect(messages.size).to eq(2)
    end

    it 'never adds an empty system message (# PRD-20260918-api-deepseek-structured-output AC-005)' do
      messages = generated_body(plain_request)['messages']

      expect(messages.map { |message| message['role'] }).to eq(['user'])
    end
  end

  describe '#test_connection' do
    def connection_returning(response)
      double('Faraday::Connection').tap do |conn|
        allow(conn).to receive(:get).and_yield(double('Faraday::Request', headers: {})).and_return(response)
      end
    end

    def connection_raising(error)
      double('Faraday::Connection').tap do |conn|
        allow(conn).to receive(:get).and_raise(error)
      end
    end

    it 'reports verified for a successful response (# PRD-20260918-api-deepseek-structured-output AC-006)' do
      allow(adapter).to receive(:build_connection).and_return(connection_returning(double('response', success?: true)))

      result = adapter.test_connection(integration)

      expect(result[:success]).to be true
      expect(result[:status]).to eq('verified')
      expect(result[:latency_ms]).to be_a(Integer)
    end

    it 'derives the status from the response instead of hardcoding verified (# PRD-20260918-api-deepseek-structured-output AC-006)' do
      allow(adapter).to receive(:build_connection).and_return(connection_returning(double('response', success?: false)))

      result = adapter.test_connection(integration)

      expect(result[:success]).to be false
      expect(result[:status]).to eq('error')
      expect(result[:error]).to be_present
    end

    it 'returns a structured failure instead of raising on provider 5xx (# PRD-20260918-api-deepseek-structured-output AC-007)' do
      allow(adapter).to receive(:build_connection).and_return(connection_raising(Faraday::ServerError.new('boom')))

      result = adapter.test_connection(integration)

      expect(result[:success]).to be false
      expect(result[:status]).to eq('error')
      expect(result[:error]).to be_present
      expect(result[:latency_ms]).to be_nil
    end

    it 'returns a structured failure instead of raising when the host is unreachable (# PRD-20260918-api-deepseek-structured-output AC-008)' do
      allow(adapter).to receive(:build_connection).and_return(connection_raising(Faraday::ConnectionFailed.new('no route')))

      result = adapter.test_connection(integration)

      expect(result[:success]).to be false
      expect(result[:status]).to eq('error')
      expect(result[:error]).to be_present
    end

    it 'still reports invalid credentials for a 401 (# PRD-20260918-api-deepseek-structured-output AC-009)' do
      allow(adapter).to receive(:build_connection).and_return(connection_raising(Faraday::UnauthorizedError.new('401')))

      result = adapter.test_connection(integration)

      expect(result[:success]).to be false
      expect(result[:status]).to eq('invalid_credentials')
    end
  end
end
