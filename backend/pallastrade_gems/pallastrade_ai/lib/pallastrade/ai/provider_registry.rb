# frozen_string_literal: true

module PallasTrade
  module AI
    # ProviderRegistry manages code-level registration of AI provider types.
    # Each registered provider specifies its Integration STI class, Adapter,
    # catalog, and metadata. This is not a database table 鈥?it's a code registry.
    class ProviderRegistry
      Entry = Struct.new(
        :key,
        :display_name,
        :integration_class,
        :adapter_class,
        :catalog_class,
        :default_base_url,
        :secret_fields,
        :non_secret_settings,
        :connection_test_strategy,
        :recommended_models,
        :supported_input_modalities,
        :supported_capabilities,
        :supported_parameters,
        :default_timeout_seconds,
        :retryable_errors,
        keyword_init: true
      )

      def initialize
        @providers = {}
      end

      # Register a provider type.
      #
      # @param key [Symbol] stable provider key, e.g. :deepseek
      # @param integration_class [String] STI class name
      # @param adapter_class [String] Adapter class name
      # @param catalog_class [String] Catalog class name
      # @param display_name [String] human-readable name
      # @param default_base_url [String] default API base URL
      # @param secret_fields [Array<Symbol>] fields treated as secrets
      # @param non_secret_settings [Hash] non-sensitive configurable settings with defaults
      # @param connection_test_strategy [Symbol] :minimal_request | :list_models
      # @param recommended_models [Array<Hash>] catalog models
      # @param supported_input_modalities [Array<Symbol>] e.g. [:text]
      # @param supported_capabilities [Array<Symbol>] e.g. [:structured_output]
      # @param supported_parameters [Array<Symbol>] canonical parameters
      # @param default_timeout_seconds [Integer]
      # @param retryable_errors [Array<Symbol>] e.g. [:timeout, :rate_limited, :server_error]
      def register(
        key,
        integration_class:,
        adapter_class:,
        catalog_class: nil,
        display_name: key.to_s.titleize,
        default_base_url: nil,
        secret_fields: [:api_key],
        non_secret_settings: {},
        connection_test_strategy: :minimal_request,
        recommended_models: [],
        supported_input_modalities: [:text],
        supported_capabilities: [:text],
        supported_parameters: [],
        default_timeout_seconds: 60,
        retryable_errors: %i[timeout server_error]
      )
        raise ArgumentError, "Provider :#{key} is already registered" if @providers.key?(key)

        @providers[key] = Entry.new(
          key: key,
          display_name: display_name,
          integration_class: integration_class,
          adapter_class: adapter_class,
          catalog_class: catalog_class,
          default_base_url: default_base_url,
          secret_fields: secret_fields,
          non_secret_settings: non_secret_settings,
          connection_test_strategy: connection_test_strategy,
          recommended_models: recommended_models,
          supported_input_modalities: supported_input_modalities,
          supported_capabilities: supported_capabilities,
          supported_parameters: supported_parameters,
          default_timeout_seconds: default_timeout_seconds,
          retryable_errors: retryable_errors
        )
      end

      # Look up a registered provider by key.
      # @param key [Symbol, String]
      # @return [Entry, nil]
      def [](key)
        @providers[key.to_sym]
      end

      # All registered providers.
      # @return [Array<Entry>]
      def all
        @providers.values
      end

      # Registered provider keys.
      # @return [Array<Symbol>]
      def keys
        @providers.keys
      end

      # Check if a provider key is registered.
      def registered?(key)
        @providers.key?(key.to_sym)
      end

      # Resolve the Integration STI class for a registered provider key.
      # 反射（constantize）集中在此处，避免 controller 对参数派生值直接反射
      #（Brakeman UnsafeReflection）。调用方必须先 `registered?`/`[]` 校验 key。
      # @param key [Symbol, String] registered provider key
      # @return [Class, nil]
      def integration_class_for(key)
        entry = @providers[key.to_sym]
        entry&.integration_class&.safe_constantize
      end

      # Get the list of allowed provider keys for API validation.
      def allowed_keys
        @providers.keys.map(&:to_s)
      end
    end
  end
end
