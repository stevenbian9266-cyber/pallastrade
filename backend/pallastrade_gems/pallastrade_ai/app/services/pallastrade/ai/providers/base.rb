# frozen_string_literal: true

module PallasTrade
  module AI
    module Providers
      # Abstract base class for all AI provider adapters.
      # Each provider type (DeepSeek, OpenAI, etc.) must implement this contract.
      # All adapters are tested against a unified contract spec.
      class Base
        # Validate that the integration configuration is valid.
        # @param integration [PallasTrade::Integration]
        # @raise [PallasTrade::AI::Errors::ConfigurationInvalid]
        def validate_configuration!(integration)
          raise NotImplementedError
        end

        # Test connection with a lightweight, non-generative request.
        # @param integration [PallasTrade::Integration]
        # @return [Hash] { success: Boolean, status: String, error: String, latency_ms: Integer }
        def test_connection(integration)
          raise NotImplementedError
        end

        # Execute a generation request.
        # @param integration [PallasTrade::Integration]
        # @param request [PallasTrade::AI::Providers::Request]
        # @return [PallasTrade::AI::Providers::Response]
        def generate(integration, request)
          raise NotImplementedError
        end

        # List of canonical parameters this provider supports.
        # @return [Array<Symbol>]
        def supported_parameters
          []
        end

        # Normalize raw provider errors into stable error codes.
        # @param error [StandardError]
        # @return [Hash] { code: String, message: String, retryable: Boolean }
        def normalize_error(error)
          {
            code: 'ai_provider_unavailable',
            message: error.message&.truncate(500),
            retryable: false
          }
        end

        # Estimate cost based on token usage and pricing snapshot.
        # @param usage [Hash] { input_tokens:, output_tokens:, ... }
        # @param pricing [Hash] provider-specific pricing data
        # @return [BigDecimal] estimated cost in USD
        def estimate_cost(usage, pricing: {})
          0.0
        end

        # Build a Faraday connection for this provider.
        # @param integration [PallasTrade::Integration]
        # @return [Faraday::Connection]
        def build_connection(integration)
          Faraday.new(url: integration.preferred_base_url) do |conn|
            conn.options.open_timeout = integration.preferred_open_timeout_seconds || 5
            conn.options.timeout = integration.preferred_read_timeout_seconds || 60

            conn.request :json
            conn.response :json
            conn.response :raise_error

            # SSRF protection middleware
conn.use PallasTrade::AI::Middleware::SsrfProtection

            conn.adapter Faraday.default_adapter
          end
        end
      end
    end
  end
end
