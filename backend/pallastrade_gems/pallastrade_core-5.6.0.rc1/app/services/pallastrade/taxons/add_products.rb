module PallasTrade
  module Taxons
    class AddProducts
      prepend PallasTrade::ServiceModule::Base

      # Creates classifications for the given taxons and products in bulk.
      #
      # @param taxons [Array<PallasTrade::Taxon>]
      # @param products [Array<PallasTrade::Product>]
      # @return [PallasTrade::ServiceModule::Base::Result]
      def call(taxons:, products:)
        return if taxons.blank? || products.blank?

        # build the params for the insert_all
        classifications_params = taxons.pluck(:id).flat_map do |taxon_id|
          position = PallasTrade::Classification.where(taxon_id: taxon_id).count

          products.pluck(:id).map do |product_id|
            {
              taxon_id: taxon_id,
              product_id: product_id,
              position: (position += 1),
              created_at: Time.current,
              updated_at: Time.current
            }
          end
        end
        # doing a quick insert_all here to avoid the overhead of instantiating
        PallasTrade::Classification.insert_all(classifications_params)

        # update counter caches
        taxon_ids = taxons.pluck(:id)
        product_ids = products.pluck(:id)
        taxon_ids.each { |id| PallasTrade::Taxon.reset_counters(id, :classifications) }
        product_ids.each { |id| PallasTrade::Product.reset_counters(id, :classifications) }
        # Recompute the descendant-inclusive products_count for the taxons and
        # their ancestors (bulk insert skips Classification callbacks).
        PallasTrade::Taxon.recalculate_products_count(taxon_ids)

        # clear cache & index products
        PallasTrade::Product.where(id: product_ids).touch_all
        products.each(&:enqueue_search_index)

        PallasTrade::Taxon.where(id: taxon_ids).touch_all
        PallasTrade::Taxons::TouchFeaturedSections.call(taxon_ids: taxon_ids) if defined?(PallasTrade::Taxons::TouchFeaturedSections)

        success(true)
      end
    end
  end
end
