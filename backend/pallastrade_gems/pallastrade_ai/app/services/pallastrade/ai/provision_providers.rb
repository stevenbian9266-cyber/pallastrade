# frozen_string_literal: true

module PallasTrade
  module AI
    # Lazy provisioning of preset AI provider configurations for a store.
    #
    # When an admin first visits the AI providers page, every registered
    # provider type (DeepSeek, OpenAI, etc.) must already have a store-scoped
    # Provider record — even if inactive and without credentials — so the
    # UI can show preset cards with "Key not configured" status.
    #
    # This service is idempotent: calling it multiple times only creates
    # missing records and never touches existing ones.
    #
    # @example
    #   PallasTrade::AI::ProvisionProviders.call(store: current_store)
    class ProvisionProviders
      def self.call(store:)
        new(store).call
      end

      def initialize(store)
        @store = store
      end

      def call
        PallasTrade::AI.providers.all.each do |entry|
          klass = entry.provider_class.constantize
          next if @store.ai_providers.exists?(type: klass.name)

          # Provider has no name column — display_name is derived from
          # the STI class (integration_name), so only store + active are set.
          klass.create!(
            store: @store,
            active: false
          )
        end
      end
    end
  end
end
