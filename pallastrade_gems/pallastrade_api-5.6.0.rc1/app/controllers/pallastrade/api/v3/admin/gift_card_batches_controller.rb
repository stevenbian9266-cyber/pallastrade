module PallasTrade
  module Api
    module V3
      module Admin
        # Admin bulk-issue endpoint for `PallasTrade::GiftCardBatch`. Creating a
        # batch synchronously generates the `codes_count` gift cards inline
        # (or kicks off a background job when the count exceeds
        # `PallasTrade.config.gift_card_batch_web_limit`, default 500). Read-only
        # access lives behind `list`/`show` so the SPA can surface batch
        # context on the gift cards index (filter chip, batch chip on rows).
        class GiftCardBatchesController < ResourceController
          scoped_resource :gift_cards

          protected

          def model_class
            PallasTrade::GiftCardBatch
          end

          def serializer_class
            PallasTrade.api.admin_gift_card_batch_serializer
          end

          def permitted_params
            params.permit(:prefix, :codes_count, :amount, :expires_at, :currency)
          end
        end
      end
    end
  end
end
