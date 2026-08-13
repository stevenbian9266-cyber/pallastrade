# frozen_string_literal: true

module PallasTrade
  module AI
    # Checks the five-level availability gates for an AI capability.
    # No side effects 鈥?does not create Runs, does not call external providers.
    class AvailabilityService
      # @param capability [String] capability key
      # @param store [PallasTrade::Store]
      # @param actor [PallasTrade::AdminUser, nil]
      # @param resource [Object, nil]
      # @return [Hash] { available: Boolean, reason: String, details: Hash }
      def self.check(capability:, store:, actor: nil, resource: nil)
        new(capability, store, actor, resource).check
      end

      def initialize(capability, store, actor, resource)
        @capability_key = capability.to_s
        @store = store
        @actor = actor
        @resource = resource
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def check
        # Gate 0: Capability must be registered
        unless PallasTrade::AI.capabilities.registered?(@capability_key)
          return unavailable(:ai_capability_disabled, 'Capability is not registered')
        end

        # Gate 1: System kill switch
        unless PallasTradeAI::Config.system_enabled?
          return unavailable(:ai_disabled, 'AI system is disabled globally')
        end

        # Gate 2: Store AI switch
        setting = PallasTrade::AI::Setting.find_by(store: @store)
        unless setting&.active?
          return unavailable(:ai_disabled, 'AI is disabled for this store')
        end

        # Gate 3: Capability setting
        cap_setting = PallasTrade::AI::CapabilitySetting.find_by(
          store: @store,
          capability_key: @capability_key
        )
        unless cap_setting&.active?
          return unavailable(:ai_capability_disabled, 'Capability is disabled')
        end

        # Gate 4: Primary model must be set
        primary_model = cap_setting.primary_model
        unless primary_model
          return unavailable(:ai_model_disabled, 'No primary model configured for this capability')
        end

        # Gate 5: Provider must be active
        provider = primary_model.provider
        unless provider&.active?
          return unavailable(:ai_provider_disabled, 'AI provider is disabled')
        end

        # Gate 6: Model must be active
        unless primary_model.active?
          return unavailable(:ai_model_disabled, 'AI model is disabled')
        end

        # Gate 7: Credentials must be configured
        provider_secret = PallasTrade::AI::ProviderSecret.find_by(provider: provider)
        unless provider_secret&.configured?
          return unavailable(:ai_credentials_missing, 'Provider credentials are not configured')
        end

        # Gate 8: Budget check
        if budget_exceeded?(setting, cap_setting)
          return unavailable(:ai_budget_exceeded, 'Daily budget or token limit exceeded')
        end

        # Gate 9: Check concurrency limit
        if concurrency_exceeded?(provider)
          return unavailable(:ai_rate_limited, 'Provider concurrency limit reached')
        end

        # Gate 10: Resource authorization (if capability specifies it)
        capability_entry = PallasTrade::AI.capabilities[@capability_key]
        if capability_entry&.authorization.present? && @actor.present? && @resource.present?
          auth = capability_entry.authorization
          # Authorization check is done by the caller 鈥?we only validate presence here.
          # The Gateway will enforce CanCanCan authorization.
        end

        # All gates passed
        {
          available: true,
          reason: nil,
          details: {
            capability_key: @capability_key,
            store_id: @store.id,
            provider_type: provider.type,
            provider_id: provider.id,
            model_id: primary_model.id,
            provider_model_id: primary_model.provider_model_id,
            setting_id: setting.id,
            capability_setting_id: cap_setting.id
          }
        }
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def unavailable(code, message)
        {
          available: false,
          reason: code,
          details: {
            message: message,
            capability_key: @capability_key,
            store_id: @store&.id
          }
        }
      end

      def budget_exceeded?(setting, cap_setting)
        today = Time.current.beginning_of_day..Time.current.end_of_day

        # Check store-level limits
        if setting.daily_request_limit
          count = PallasTrade::AI::Run.where(store: @store, created_at: today).count
          return true if count >= setting.daily_request_limit
        end

        if setting.daily_cost_limit
          total = PallasTrade::AI::Run.where(store: @store, created_at: today)
                                     .sum(:estimated_cost)
          return true if total >= setting.daily_cost_limit
        end

        # Check capability-level limits
        if cap_setting.daily_request_limit
          count = PallasTrade::AI::Run.where(store: @store, capability_key: @capability_key, created_at: today).count
          return true if count >= cap_setting.daily_request_limit
        end

        if cap_setting.daily_token_limit
          total = PallasTrade::AI::Run.where(store: @store, capability_key: @capability_key, created_at: today)
                                     .sum(:output_tokens)
          return true if total >= cap_setting.daily_token_limit
        end

        false
      end

      def concurrency_exceeded?(provider)
        limit = provider.preferred_concurrency_limit || PallasTradeAI::Config.default_concurrency_limit
        running = PallasTrade::AI::Run.where(provider_id: provider.id, status: 'running').count
        running >= limit
      end
    end
  end
end
