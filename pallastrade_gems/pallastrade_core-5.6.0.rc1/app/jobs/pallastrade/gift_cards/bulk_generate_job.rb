module PallasTrade
  module GiftCards
    class BulkGenerateJob < ::PallasTrade::BaseJob
      queue_as PallasTrade.queues.gift_cards

      def perform(id)
        gift_cards_batch = PallasTrade::GiftCardBatch.find(id)

        gift_cards_batch.create_gift_cards
      end
    end
  end
end
