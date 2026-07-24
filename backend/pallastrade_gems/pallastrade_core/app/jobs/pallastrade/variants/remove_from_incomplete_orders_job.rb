module PallasTrade
  module Variants
    class RemoveFromIncompleteOrdersJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.variants

      def perform(variant)
        PallasTrade::Variants::RemoveLineItems.call(variant: variant)
      end
    end
  end
end
