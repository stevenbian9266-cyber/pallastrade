module PallasTrade
  module GiftCards
    class Redeem
      prepend PallasTrade::ServiceModule::Base

      def call(gift_card:)
        if gift_card.amount_remaining.zero?
          gift_card.redeem!
        else
          gift_card.partial_redeem!
        end

        success(gift_card)
      end
    end
  end
end
