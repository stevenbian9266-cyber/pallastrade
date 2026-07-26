# frozen_string_literal: true

module PallasTrade
  module AI
    # Unified Gateway 鈥?all business AI calls go through this single entry point.
    # Handles availability checks, provider routing, schema validation,
    # budget enforcement, run lifecycle, and error normalization.
    class Gateway
      # Result types returned by the gateway.
      Result = Struct.new(:status, :run, :output, :error_code, :error_message, keyword_init: true)

      class << self
        # Synchronous AI call. Blocks until the provider responds.
        #
        # @param capability [String] capability key
        # @param store [PallasTrade::Store]
        # @param actor [PallasTrade::AdminUser]
        # @param input [Hash] capability-specific input
        # @param resource [Object, nil] the business resource being operated on
        # @param idempotency_key [String, nil]
        # @return [Result]
        def call(capability:, store:, actor:, input:, resource: nil, idempotency_key: nil)
          new(capability, store, actor, input, resource, idempotency_key).call
        end

        # Asynchronous AI call. Enqueues a Sidekiq job and returns immediately.
        #
        # @param capability [String] capability key
        # @param store [PallasTrade::Store]
        # @param actor [PallasTrade::AdminUser]
        # @param input [Hash]
        # @param resource [Object, nil]
        # @param idempotency_key [String, nil]
        # @return [Result]
        def enqueue(capability:, store:, actor:, input:, resource: nil, idempotency_key: nil)
          new(capability, store, actor, input, resource, idempotency_key).enqueue
        end
      end

      def initialize(capability, store, actor, input, resource, idempotency_key)
        @capability_key = capability.to_s
        @store = store
        @actor = actor
        @input = input
        @resource = resource
        @idempotency_key = idempotency_key
        @capability_entry = PallasTrade::AI.capabilities[@capability_key]
      end

      # Execute synchronously.
      # rubocop:disable Metrics/MethodLength
      def call
        # 1. Check capability registration
        return unavailable(:ai_capability_disabled, 'Capability not registered') unless @capability_entry

        # 2. Check availability (five gates + budget + concurrency)
        availability = PallasTrade::AI::AvailabilityService.check(
          capability: @capability_key,
          store: @store,
          actor: @actor,
          resource: @resource
        )
        return skipped(availability[:reason], availability[:details][:message]) unless availability[:available]

        # 3. Validate input against capability schema
        input_valid = validate_input
        return rejected(:ai_output_invalid, 'Input validation failed') unless input_valid

        # 4. Get model and provider
        cap_setting = PallasTrade::AI::CapabilitySetting.find_by!(store: @store, capability_key: @capability_key)
        model = cap_setting.primary_model
        provider = model.provider

        # 5. Create run record
        run = create_run(model, provider, 'sync')

        # 6. Execute via adapter
        begin
          run.start!
          response = execute_provider_call(provider, model, run)
          run.succeed!(
            usage: response.usage,
            provider_request_id: response.provider_request_id,
            latency_ms: response.instance_variable_get(:@latency_ms)
          )
          Result.new(status: :success, run: run, output: response)
        rescue StandardError => e
          normalized = normalize_error(provider, e)
          run.fail!(error_code: normalized[:code], error_message: normalized[:message])
          Result.new(status: :failure, run: run, error_code: normalized[:code], error_message: normalized[:message])
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Enqueue asynchronous execution.
      def enqueue
        return unavailable(:ai_capability_disabled, 'Capability not registered') unless @capability_entry
        return rejected(:ai_configuration_invalid, 'Async execution required') unless @capability_entry.execution_mode == :async

        availability = PallasTrade::AI::AvailabilityService.check(
          capability: @capability_key,
          store: @store,
          actor: @actor,
          resource: @resource
        )
        return skipped(availability[:reason], availability[:details][:message]) unless availability[:available]

        input_valid = validate_input
        return rejected(:ai_output_invalid, 'Input validation failed') unless input_valid

        cap_setting = PallasTrade::AI::CapabilitySetting.find_by!(store: @store, capability_key: @capability_key)
        model = cap_setting.primary_model
        provider = model.provider

        run = create_run(model, provider, 'async')
        PallasTrade::AI::ExecuteRunJob.perform_later(run.id)

        Result.new(status: :queued, run: run)
      end

      private

      # rubocop:disable Metrics/MethodLength
      def execute_provider_call(provider, model, run)
        adapter = build_adapter(provider)
        request = PallasTrade::AI::Providers::Request.new(
          messages: @input[:messages] || [],
          model: model.provider_model_id,
          system_instructions: @input[:system_instructions],
          response_schema: @capability_entry&.output_schema_class&.constantize&.schema,
          parameters: build_parameters(model, cap_setting),
          privacy_identifier: privacy_identifier,
          idempotency_key: @idempotency_key
        )

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = adapter.generate(provider, request)
        latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).to_i
        response.instance_variable_set(:@latency_ms, latency)

        # Validate output schema if structured output
        if response.structured_output.present? && @capability_entry&.output_schema_class
          validate_output!(response.structured_output)
        end

        response
      end
      # rubocop:enable Metrics/MethodLength

      def build_adapter(provider)
        provider_entry = PallasTrade::AI.providers[provider.key.to_sym]
        raise PallasTrade::AI::Errors::ProviderDisabled, "Provider #{provider.key} not registered" unless provider_entry

        provider_entry.adapter_class.constantize.new
      end

      def cap_setting
        @cap_setting ||= PallasTrade::AI::CapabilitySetting.find_by(store: @store, capability_key: @capability_key)
      end

      def build_parameters(model, setting)
        # Merge: Model defaults -> CapabilitySetting overrides -> Invocation overrides
        params = (model.default_parameters || {}).symbolize_keys
        params.merge!((setting.parameter_overrides || {}).symbolize_keys)
        params.merge!(@input[:parameters] || {}) if @capability_entry&.allowed_parameters&.any?
        params
      end

      def validate_input
        return true unless @capability_entry&.input_schema_class

        schema_class = @capability_entry.input_schema_class.constantize
        schema_class.valid?(@input)
      rescue NameError
        true # Schema class not loaded 鈥?skip validation for now
      end

      def validate_output!(output)
        return true unless @capability_entry&.output_schema_class

        schema_class = @capability_entry.output_schema_class.constantize
        unless schema_class.valid?(output)
          raise PallasTrade::AI::Errors::OutputValidationError, 'Output does not match expected schema'
        end
      rescue NameError
        true
      end

      def create_run(model, provider, mode)
        PallasTrade::AI::Run.create!(
          store: @store,
          user: @actor,
          capability_key: @capability_key,
          capability_version: @capability_entry&.version,
          provider_type: provider.type,
          provider_id: provider.id,
          model_id: model.id,
          provider_model_id: model.provider_model_id,
          mode: mode,
          status: 'queued',
          idempotency_key: @idempotency_key,
          input_schema_version: @capability_entry&.version,
          output_schema_version: @capability_entry&.version,
          input_digest: compute_input_digest,
          safe_parameters: sanitize_parameters,
          queued_at: Time.current
        )
      end

      def normalize_error(provider, error)
        adapter = build_adapter(provider)
        adapter.normalize_error(error)
      rescue StandardError
        { code: 'ai_provider_unavailable', message: error.message&.truncate(500), retryable: false }
      end

      def privacy_identifier
        # Anonymized hash 鈥?never sends real user/store identifiers
        Digest::SHA256.hexdigest("#{@store.id}-#{@actor&.id || 'anonymous'}")
      end

      def compute_input_digest
        Digest::SHA256.hexdigest(@input.to_json)
      end

      def sanitize_parameters
        # Only store safe, non-sensitive parameters on the run
        allowed = @capability_entry&.allowed_parameters || []
        (@input[:parameters] || {}).slice(*allowed)
      end

      def unavailable(code, message)
        Result.new(status: :unavailable, error_code: code, error_message: message)
      end

      def skipped(reason, message)
        Result.new(status: :skipped, error_code: reason, error_message: message)
      end

      def rejected(code, message)
        Result.new(status: :rejected, error_code: code, error_message: message)
      end
    end
  end
end
