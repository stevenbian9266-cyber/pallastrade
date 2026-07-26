# frozen_string_literal: true

module PallasTrade
  module AI
    # CapabilityRegistry manages code-level registration of business AI capabilities.
    # Each capability declares its handler, input/output schemas, authorization,
    # execution mode, and required model capabilities.
    class CapabilityRegistry
      Entry = Struct.new(
        :key,
        :display_name,
        :description,
        :version,
        :handler_class,
        :input_schema_class,
        :output_schema_class,
        :authorization,
        :execution_mode,
        :allowed_parameters,
        :required_model_capabilities,
        :data_classification,
        keyword_init: true
      )

      def initialize
        @capabilities = {}
      end

      # Register a business capability.
      #
      # @param key [String] stable capability key, e.g. 'catalog.translate'
      # @param handler [String] handler class name
      # @param input_schema [String] input schema class name
      # @param output_schema [String] output schema class name
      # @param authorization [Hash] { action: Symbol, subject: String }
      # @param execution [Symbol] :sync | :async
      # @param allowed_parameters [Array<Symbol>] parameters admin can override
      # @param required_model_capabilities [Array<Symbol>] required model features
      # @param display_name [String] human-readable name
      # @param description [String] description of the capability
      # @param data_classification [String] public | internal | personal | sensitive | payment_restricted
      # @param version [String] semver version
      def register(
        key,
        handler:,
        input_schema:,
        output_schema:,
        authorization: {},
        execution: :async,
        allowed_parameters: [],
        required_model_capabilities: [:text],
        display_name: key.titleize,
        description: '',
        data_classification: 'internal',
        version: '1.0.0'
      )
        raise ArgumentError, "Capability '#{key}' is already registered" if @capabilities.key?(key)

        @capabilities[key] = Entry.new(
          key: key,
          display_name: display_name,
          description: description,
          version: version,
          handler_class: handler,
          input_schema_class: input_schema,
          output_schema_class: output_schema,
          authorization: authorization,
          execution_mode: execution,
          allowed_parameters: allowed_parameters,
          required_model_capabilities: required_model_capabilities,
          data_classification: data_classification
        )
      end

      # Look up a registered capability by key.
      # @param key [String]
      # @return [Entry, nil]
      def [](key)
        @capabilities[key.to_s]
      end

      # All registered capabilities.
      # @return [Array<Entry>]
      def all
        @capabilities.values
      end

      # Registered capability keys.
      # @return [Array<String>]
      def keys
        @capabilities.keys
      end

      # Check if a capability key is registered.
      def registered?(key)
        @capabilities.key?(key.to_s)
      end
    end
  end
end
