# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalogs
      # Catalog of recommended DeepSeek models and their metadata.
      module DeepSeek
        MODELS = [
          {
            provider_model_id: 'deepseek-v4-flash',
            name: 'DeepSeek V4 Flash',
            kind: 'text',
            capabilities: %w[text structured_output],
            default_parameters: {
              max_output_tokens: 8192,
              temperature: 0.7
            },
            description: 'Default high-throughput model for routine AI tools.',
            pricing: {
              input_per_1k_tokens: 0.00014,
              output_per_1k_tokens: 0.00028,
              cached_input_per_1k_tokens: 0.000014,
              currency: 'USD',
              effective_date: '2026-07-24'
            }
          },
          {
            provider_model_id: 'deepseek-v4-pro',
            name: 'DeepSeek V4 Pro',
            kind: 'text',
            capabilities: %w[text structured_output reasoning],
            default_parameters: {
              max_output_tokens: 16384,
              temperature: 0.7,
              reasoning_effort: 'medium'
            },
            description: 'High-quality model for complex reasoning tasks.',
            pricing: {
              input_per_1k_tokens: 0.00055,
              output_per_1k_tokens: 0.00219,
              cached_input_per_1k_tokens: 0.000055,
              currency: 'USD',
              effective_date: '2026-07-24'
            }
          }
        ].freeze

        DEPRECATED_MODEL_IDS = %w[deepseek-chat deepseek-reasoner].freeze

        SUPPORTED_PARAMETERS = %i[
          max_output_tokens temperature reasoning_effort
          thinking response_format stream stop
        ].freeze

        RETRYABLE_ERRORS = %i[timeout rate_limited server_error].freeze
      end
    end
  end
end
