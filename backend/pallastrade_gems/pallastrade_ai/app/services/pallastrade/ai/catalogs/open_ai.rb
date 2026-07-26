# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalogs
      # Catalog of recommended OpenAI (GPT) models and their metadata.
      module OpenAI
        MODELS = [
          {
            provider_model_id: 'gpt-5.6-sol',
            name: 'GPT-5.6 Sol',
            kind: 'text',
            capabilities: %w[text structured_output reasoning],
            default_parameters: {
              max_output_tokens: 16384,
              temperature: 0.7
            },
            description: 'Complex, quality-first work 鈥?reasoning, analysis, structured generation.',
            pricing: {
              input_per_1k_tokens: 0.005,
              output_per_1k_tokens: 0.015,
              cached_input_per_1k_tokens: 0.0025,
              currency: 'USD',
              effective_date: '2026-07-24'
            }
          },
          {
            provider_model_id: 'gpt-5.6-terra',
            name: 'GPT-5.6 Terra',
            kind: 'text',
            capabilities: %w[text structured_output],
            default_parameters: {
              max_output_tokens: 8192,
              temperature: 0.7
            },
            description: 'Balanced quality, latency, and cost for general-purpose tasks.',
            pricing: {
              input_per_1k_tokens: 0.00125,
              output_per_1k_tokens: 0.005,
              cached_input_per_1k_tokens: 0.000625,
              currency: 'USD',
              effective_date: '2026-07-24'
            }
          },
          {
            provider_model_id: 'gpt-5.6-luna',
            name: 'GPT-5.6 Luna',
            kind: 'text',
            capabilities: %w[text structured_output],
            default_parameters: {
              max_output_tokens: 4096,
              temperature: 0.7
            },
            description: 'High-throughput, cost-sensitive tasks 鈥?classification, extraction, routing.',
            pricing: {
              input_per_1k_tokens: 0.0003,
              output_per_1k_tokens: 0.0012,
              cached_input_per_1k_tokens: 0.00015,
              currency: 'USD',
              effective_date: '2026-07-24'
            }
          }
        ].freeze

        DEPRECATED_MODEL_IDS = %w[].freeze

        SUPPORTED_PARAMETERS = %i[
          max_output_tokens temperature reasoning_effort
          response_format stream stop seed
        ].freeze

        RETRYABLE_ERRORS = %i[timeout rate_limited server_error].freeze
      end
    end
  end
end
