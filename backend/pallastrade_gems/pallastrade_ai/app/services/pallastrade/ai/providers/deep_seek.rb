# frozen_string_literal: true

module PallasTrade
  module AI
    module Providers
      # DeepSeek adapter using OpenAI-compatible Chat Completions API.
      # Maps canonical parameters to DeepSeek-specific fields.
      class DeepSeek < Base
        # @return [Array<Symbol>]
        def supported_parameters
          PallasTrade::AI::Catalogs::DeepSeek::SUPPORTED_PARAMETERS
        end

        # @param integration [PallasTrade::AI::Provider::DeepSeek]
        # @raise [PallasTrade::AI::Errors::CredentialsError]
        def validate_configuration!(integration)
          unless integration.is_a?(PallasTrade::AI::Provider::DeepSeek)
            raise PallasTrade::AI::Errors::CredentialsError, 'Integration is not a DeepSeek provider'
          end

          unless integration.can_connect?
            raise PallasTrade::AI::Errors::CredentialsError, 'DeepSeek provider is not active or credentials are missing'
          end
        end

        # @param integration [PallasTrade::AI::Provider::DeepSeek]
        # @return [Hash]
        def test_connection(integration)
          validate_configuration!(integration)

          conn = build_connection(integration)
          api_key = integration.decrypted_api_key

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{api_key}"
            req.headers['Content-Type'] = 'application/json'
          end
          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).to_i

          {
            success: response.success?,
            status: 'verified',
            latency_ms: latency_ms,
            error: nil
          }
        rescue Faraday::UnauthorizedError
          {
            success: false,
            status: 'invalid_credentials',
            error: 'Invalid API key 鈥?authentication failed',
            latency_ms: nil
          }
        rescue Faraday::TimeoutError
          {
            success: false,
            status: 'timeout',
            error: 'Connection timed out 鈥?check network and API endpoint',
            latency_ms: nil
          }
        rescue Faraday::ClientError => e
          {
            success: false,
            status: 'error',
            error: "Connection failed: #{e.message&.truncate(200)}",
            latency_ms: nil
          }
        end

        # @param integration [PallasTrade::AI::Provider::DeepSeek]
        # @param request [PallasTrade::AI::Providers::Request]
        # @return [PallasTrade::AI::Providers::Response]
        def generate(integration, request)
          validate_configuration!(integration)

          conn = build_connection(integration)
          api_key = integration.decrypted_api_key

          body = build_request_body(request)
          headers = build_request_headers(api_key)

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raw = conn.post('chat/completions') do |req|
            req.headers.merge!(headers)
            req.body = body.to_json
          end
          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).to_i

          parse_response(raw.body, latency_ms)
        end

        # @param error [StandardError]
        # @return [Hash]
        def normalize_error(error)
          case error
          when Faraday::UnauthorizedError
            { code: 'ai_credentials_invalid', message: 'Authentication failed', retryable: false }
          when Faraday::TimeoutError
            { code: 'ai_provider_unavailable', message: 'Request timed out', retryable: true }
          when Faraday::ClientError
            { code: 'ai_provider_unavailable', message: error.message&.truncate(500), retryable: false }
          when Faraday::ServerError
            { code: 'ai_provider_unavailable', message: 'Provider server error', retryable: true }
          else
            { code: 'ai_provider_unavailable', message: error.message&.truncate(500), retryable: false }
          end
        end

        # @param usage [Hash]
        # @param pricing [Hash]
        # @return [Float]
        def estimate_cost(usage, pricing: {})
          input_cost = (usage[:input_tokens].to_f / 1000) * (pricing[:input_per_1k_tokens] || 0)
          output_cost = (usage[:output_tokens].to_f / 1000) * (pricing[:output_per_1k_tokens] || 0)
          cached_cost = (usage[:cached_input_tokens].to_f / 1000) * (pricing[:cached_input_per_1k_tokens] || 0)

          (input_cost + output_cost + cached_cost).round(6)
        end

        private

        def build_request_body(request)
          body = {
            model: request.model,
            messages: request.messages,
            stream: false
          }

          body[:max_tokens] = request.parameters[:max_output_tokens] if request.parameters[:max_output_tokens]
          body[:temperature] = request.parameters[:temperature] if request.parameters[:temperature]
          body[:stop] = request.parameters[:stop] if request.parameters[:stop]

          # DeepSeek-specific: thinking/reasoning_effort
          if request.parameters[:thinking] && request.parameters[:reasoning_effort]
            body[:thinking] = { type: request.parameters[:reasoning_effort] }
          end

          # Structured output via response_format
          if request.response_schema
            body[:response_format] = {
              type: 'json_schema',
              json_schema: request.response_schema
            }
          end

          body
        end

        def build_request_headers(api_key)
          {
            'Authorization' => "Bearer #{api_key}",
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
          }
        end

        def parse_response(body, latency_ms)
          data = body.is_a?(Hash) ? body : JSON.parse(body)
          choice = data.dig('choices', 0) || {}

          structured_output = nil
          text = choice.dig('message', 'content')

          # Try to parse structured output if present
          if text.present?
            begin
              parsed = JSON.parse(text)
              structured_output = parsed if parsed.is_a?(Hash)
            rescue JSON::ParserError
              # Not JSON, keep as plain text
            end
          end

          PallasTrade::AI::Providers::Response.new(
            text: text,
            structured_output: structured_output,
            provider_request_id: data['id'],
            provider_model_id: data['model'],
            finish_reason: choice['finish_reason'],
            usage: {
              input_tokens: data.dig('usage', 'prompt_tokens') || 0,
              output_tokens: data.dig('usage', 'completion_tokens') || 0,
              cached_input_tokens: data.dig('usage', 'prompt_cache_hit_tokens') || 0,
              reasoning_tokens: data.dig('usage', 'completion_tokens_details', 'reasoning_tokens') || 0
            },
            safe_metadata: {
              created: data['created'],
              system_fingerprint: data['system_fingerprint']
            },
            raw_response: data
          )
        end
      end
    end
  end
end
