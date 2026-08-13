# frozen_string_literal: true

# Register preset AI providers.
# Uses ASCII-only to avoid encoding issues in Docker.
Rails.application.reloader.to_prepare do
  # Guard against double registration in dev reload
  next if PallasTrade::AI.providers.registered?(:deepseek)

  # DeepSeek provider
  PallasTrade::AI.providers.register(
    :deepseek,
    provider_class: 'PallasTrade::AI::Provider::DeepSeek',
    adapter_class: 'PallasTrade::AI::Providers::DeepSeek',
    catalog_class: 'PallasTrade::AI::Catalogs::DeepSeek',
    display_name: 'DeepSeek',
    default_base_url: 'https://api.deepseek.com',
    secret_fields: [:api_key],
    non_secret_settings: {
      base_url: { type: :string, default: 'https://api.deepseek.com' },
      open_timeout_seconds: { type: :integer, default: 5 },
      read_timeout_seconds: { type: :integer, default: 60 },
      max_retries: { type: :integer, default: 2 },
      concurrency_limit: { type: :integer, default: 5 }
    },
    connection_test_strategy: :list_models,
    recommended_models: [
      { provider_model_id: 'deepseek-v4-flash', name: 'DeepSeek V4 Flash', kind: 'text', capabilities: ['text', 'structured_output'], default_parameters: { max_output_tokens: 8192, temperature: 0.7 }, description: 'Default high-throughput model.', pricing: { input_per_1k_tokens: 0.00014, output_per_1k_tokens: 0.00028, cached_input_per_1k_tokens: 0.000014, currency: 'USD', effective_date: '2026-07-24' } },
      { provider_model_id: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro', kind: 'text', capabilities: ['text', 'structured_output', 'reasoning'], default_parameters: { max_output_tokens: 16384, temperature: 0.7, reasoning_effort: 'medium' }, description: 'High-quality model for complex reasoning.', pricing: { input_per_1k_tokens: 0.00055, output_per_1k_tokens: 0.00219, cached_input_per_1k_tokens: 0.000055, currency: 'USD', effective_date: '2026-07-24' } }
    ],
    supported_input_modalities: [:text],
    supported_capabilities: [:text, :structured_output, :reasoning],
    supported_parameters: [:max_output_tokens, :temperature, :reasoning_effort, :thinking, :response_format, :stream, :stop],
    default_timeout_seconds: 60,
    retryable_errors: [:timeout, :rate_limited, :server_error]
  )

  # OpenAI (GPT) provider
  PallasTrade::AI.providers.register(
    :openai,
    provider_class: 'PallasTrade::AI::Provider::OpenAI',
    adapter_class: 'PallasTrade::AI::Providers::OpenAI',
    catalog_class: 'PallasTrade::AI::Catalogs::OpenAI',
    display_name: 'OpenAI (GPT)',
    default_base_url: 'https://api.openai.com/v1',
    secret_fields: [:api_key],
    non_secret_settings: {
      base_url: { type: :string, default: 'https://api.openai.com/v1' },
      organization_id: { type: :string, default: '' },
      project_id: { type: :string, default: '' },
      open_timeout_seconds: { type: :integer, default: 5 },
      read_timeout_seconds: { type: :integer, default: 60 },
      max_retries: { type: :integer, default: 2 },
      concurrency_limit: { type: :integer, default: 5 },
      store_responses: { type: :boolean, default: false }
    },
    connection_test_strategy: :list_models,
    recommended_models: [
      { provider_model_id: 'gpt-5.6-sol', name: 'GPT-5.6 Sol', kind: 'text', capabilities: ['text', 'structured_output', 'reasoning'], default_parameters: { max_output_tokens: 16384, temperature: 0.7 }, description: 'Complex, quality-first work.', pricing: { input_per_1k_tokens: 0.005, output_per_1k_tokens: 0.015, cached_input_per_1k_tokens: 0.0025, currency: 'USD', effective_date: '2026-07-24' } },
      { provider_model_id: 'gpt-5.6-terra', name: 'GPT-5.6 Terra', kind: 'text', capabilities: ['text', 'structured_output'], default_parameters: { max_output_tokens: 8192, temperature: 0.7 }, description: 'Balanced quality, latency, and cost.', pricing: { input_per_1k_tokens: 0.00125, output_per_1k_tokens: 0.005, cached_input_per_1k_tokens: 0.000625, currency: 'USD', effective_date: '2026-07-24' } },
      { provider_model_id: 'gpt-5.6-luna', name: 'GPT-5.6 Luna', kind: 'text', capabilities: ['text', 'structured_output'], default_parameters: { max_output_tokens: 4096, temperature: 0.7 }, description: 'High-throughput, cost-sensitive tasks.', pricing: { input_per_1k_tokens: 0.0003, output_per_1k_tokens: 0.0012, cached_input_per_1k_tokens: 0.00015, currency: 'USD', effective_date: '2026-07-24' } }
    ],
    supported_input_modalities: [:text],
    supported_capabilities: [:text, :structured_output, :reasoning],
    supported_parameters: [:max_output_tokens, :temperature, :reasoning_effort, :response_format, :stream, :stop, :seed],
    default_timeout_seconds: 60,
    retryable_errors: [:timeout, :rate_limited, :server_error]
  )
end
