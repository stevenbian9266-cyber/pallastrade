module PallasTrade
  module CreditCards
    # @deprecated Use card.destroy directly instead. Payment cleanup is now
    #   handled by the before_destroy callback in PallasTrade::PaymentSourceConcern.
    #   This service will be removed in PallasTrade 6.0.
    class Destroy
      prepend PallasTrade::ServiceModule::Base

      def call(card:)
        PallasTrade::Deprecation.warn(
          "#{self.class.name} is deprecated and will be removed in PallasTrade 6.0. " \
          'Use card.destroy directly instead. Payment cleanup is now handled ' \
          'automatically by the before_destroy callback in PaymentSourceConcern.',
          caller_locations(2)
        )

        if card.destroy
          success(card: card)
        else
          failure(card.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
