# frozen_string_literal: true

module PallasTrade
  module Admin
    # AI Product Copilot helper (PRD-20260915-catalog-batch-e1-ai-copilot
    # FR-006): tells the product form whether a capability can be used right now.
    #
    # The admin engine must stay usable without the AI engine installed, so every
    # access is guarded — a store without `pallastrade_ai` simply renders no
    # assistant, and a store with the engine but no configuration gets a disabled
    # button plus the reason code.
    # Note: Zeitwerk resolves this file to `AIAssistHelper` (the 'AI' acronym is
    # registered in `backend/config/initializers/inflections.rb`).
    module AIAssistHelper
      # @param capability [String] capability key
      # @return [Hash, nil] `{ available:, reason: }`, or nil when the AI engine is absent
      def ai_assist_state(capability)
        return nil unless defined?(PallasTrade::AI::AvailabilityService)

        check = PallasTrade::AI::AvailabilityService.check(
          capability: capability,
          store: current_store,
          actor: ai_assist_actor
        )

        { available: check[:available], reason: check[:reason] }
      end

      # @param state [Hash, nil]
      # @return [String, nil] tooltip / label for a disabled button
      def ai_assist_reason_label(state)
        return nil if state.nil? || state[:available]

        key = "admin.products.ai.disabled_reason.#{state[:reason]}"
        PallasTrade.t(key, default: PallasTrade.t('admin.products.ai.disabled_reason.default'))
      end

      # @return [PallasTrade::AdminUser, nil]
      def ai_assist_actor
        klass = PallasTrade.admin_user_class
        return nil unless klass

        method_name = "current_#{klass.model_name.singular_route_key}"
        respond_to?(method_name) ? send(method_name) : nil
      end
    end
  end
end
