# frozen_string_literal: true

# Register test capabilities for development and testing.
# These are ONLY loaded in development/test environments.
unless Rails.env.production?
  Rails.application.reloader.to_prepare do
    # Guard against double registration on dev code reloads.
    next if PallasTrade::AI.capabilities.registered?('test.echo')

    PallasTrade::AI.capabilities.register(
      'test.echo',
      handler: 'PallasTrade::AI::Schemas::TestEcho::Handler',
      input_schema: 'PallasTrade::AI::Schemas::TestEcho::Input',
      output_schema: 'PallasTrade::AI::Schemas::TestEcho::Output',
      authorization: {},
      execution: :sync,
      allowed_parameters: %i[max_output_tokens temperature],
      required_model_capabilities: %i[text],
      display_name: 'Test Echo',
      description: 'Test capability 鈥?echoes input back as structured output. Not available in production.',
      data_classification: 'internal',
      version: '1.0.0'
    )
  end
end
