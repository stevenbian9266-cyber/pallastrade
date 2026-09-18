# frozen_string_literal: true

module PallasTrade
  module AI
    # Executes an AI run asynchronously via Sidekiq.
    # Re-checks all availability gates before making the external call.
    # Only the run's prefixed ID is passed in the job payload 鈥?no secrets.
    class ExecuteRunJob < ActiveJob::Base
      queue_as { PallasTradeAI.interactive_queue }

      # Max retries for transient failures.
      retry_on Faraday::TimeoutError, wait: :exponentially_longer, attempts: 3
      retry_on Faraday::ConnectionFailed, wait: :exponentially_longer, attempts: 3
      retry_on Faraday::ServerError, wait: :exponentially_longer, attempts: 3

      # Do not retry on these failures.
      discard_on PallasTrade::AI::Errors::CredentialsError
      discard_on PallasTrade::AI::Errors::SystemDisabled
      discard_on PallasTrade::AI::Errors::StoreDisabled
      discard_on PallasTrade::AI::Errors::ProviderDisabled
      discard_on PallasTrade::AI::Errors::ModelDisabled
      discard_on PallasTrade::AI::Errors::CapabilityDisabled

      # @param run_id [Integer] database ID of the PallasTrade::AI::Run
      def perform(run_id)
        @run = PallasTrade::AI::Run.find_by(id: run_id)
        return unless @run
        return if @run.status.in?(PallasTrade::AI::Run::TERMINAL_STATUSES)

        # Re-check availability gates 鈥?configuration may have changed since enqueue
        availability = check_availability
        unless availability[:available]
          @run.skip!(reason: availability[:reason], error_code: availability[:reason])
          return
        end

        execute!
      rescue StandardError => e
        handle_error(e)
      end

      private

      def check_availability
        PallasTrade::AI::AvailabilityService.check(
          capability: @run.capability_key,
          store: @run.store
        )
      end

      def execute!
        model = @run.model
        provider = @run.provider

        @run.start!

        # Get the capability entry for schema info
        cap_entry = PallasTrade::AI.capabilities[@run.capability_key]

        # Build the adapter
        provider_entry = PallasTrade::AI.providers[provider.key.to_sym]
        adapter = provider_entry.adapter_class.constantize.new

        # Build the request
        request = PallasTrade::AI::Providers::Request.new(
          messages: cap_entry&.handler_class&.constantize&.build_messages(@run),
          model: model.provider_model_id,
          response_schema: cap_entry&.output_schema_class&.constantize&.schema,
          parameters: @run.safe_parameters || {}
        )

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = adapter.generate(provider, request)
        latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).to_i

        # Same rule as the synchronous gateway: a capability that declares an
        # output schema must come back with a usable one, otherwise the run
        # would be recorded as a success while producing nothing.
        validate_output!(cap_entry, response)

        @run.succeed!(
          usage: response.usage,
          provider_request_id: response.provider_request_id,
          latency_ms: latency
        )

        # Store artifact if structured output is present
        if response.structured_output.present?
          @run.artifacts.create!(
            kind: 'structured_output',
            payload: response.structured_output,
            schema_version: @run.output_schema_version
          )
        end
      end

      # @param cap_entry [PallasTrade::AI::CapabilityRegistry::Entry, nil]
      # @param response [PallasTrade::AI::Providers::Response]
      # @raise [PallasTrade::AI::Errors::OutputValidationError]
      def validate_output!(cap_entry, response)
        schema_class_name = cap_entry&.output_schema_class
        return true unless schema_class_name

        schema_class = schema_class_name.constantize
        output = response.structured_output

        unless output.is_a?(Hash) && output.present?
          raise PallasTrade::AI::Errors::OutputValidationError,
                "#{@run.capability_key}: provider returned no usable structured output " \
                "(finish_reason=#{response.finish_reason.inspect})"
        end

        unless schema_class.valid?(output)
          raise PallasTrade::AI::Errors::OutputValidationError,
                "#{@run.capability_key}: output does not match #{schema_class_name}"
        end

        true
      rescue NameError
        true
      end

      def handle_error(error)
        normalized = normalize_error(error)
        @run&.fail!(error_code: normalized[:code], error_message: normalized[:message])

        # Report to Sentry with safe context.
        #
        # `defined?(Sentry)` is true whenever the gem is loaded, but `with_scope`
        # only yields a usable scope once Sentry is initialized — with no
        # SENTRY_DSN configured it yields nil, and calling `set_tags` on it
        # raised NoMethodError *after* the run had already been marked failed.
        # That turned a recorded, deterministic failure into a raising job, which
        # Sidekiq then retried. Reporting is best-effort; the run record is the
        # source of truth.
        return unless defined?(Sentry) && Sentry.initialized?

        Sentry.with_scope do |scope|
          scope.set_tags(
            ai_run_id: @run&.id,
            ai_capability: @run&.capability_key,
            ai_provider: @run&.provider_type,
            ai_model: @run&.provider_model_id,
            ai_error_code: normalized[:code]
          )
          Sentry.capture_exception(error)
        end
      end

      def output_error?(error)
        error.is_a?(PallasTrade::AI::Errors::OutputValidationError)
      end

      def normalize_error(error)
        # Output problems are deterministic and have nothing to do with provider
        # availability — answer them even when the provider cannot be resolved.
        return { code: 'ai_output_invalid', message: error.message&.truncate(500) } if output_error?(error)

        if @run&.provider
          provider_entry = PallasTrade::AI.providers[@run.provider.key.to_sym]
          if provider_entry
            adapter = provider_entry.adapter_class.constantize.new
            return adapter.normalize_error(error)
          end
        end

        { code: 'ai_provider_unavailable', message: error.message&.truncate(500) }
      end
    end
  end
end
