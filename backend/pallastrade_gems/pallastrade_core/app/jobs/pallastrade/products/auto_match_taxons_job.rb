module PallasTrade
  module Products
    class AutoMatchTaxonsJob < ::PallasTrade::BaseJob
      queue_as PallasTrade.queues.taxons

      def perform(product_id)
        product = PallasTrade::Product.find_by(id: product_id)
        return unless product.present?

        PallasTrade::Products::AutoMatchTaxons.call(product: product)
      end
    end
  end
end
