module PallasTrade
  module Taxons
    class RemoveProducts
      prepend PallasTrade::ServiceModule::Base

      # Removes the given products from the given taxons.
      #
      # @param taxons [Array<PallasTrade::Taxon>]
      # @param products [Array<PallasTrade::Product>]
      # @return [PallasTrade::ServiceModule::Base::Result]
      def call(taxons:, products:)
        return if taxons.blank? || products.blank?

        taxon_ids = taxons.pluck(:id)
        product_ids = products.pluck(:id)

        ApplicationRecord.transaction do
          taxon_ids.each do |taxon_id|
            PallasTrade::Classification.where(taxon_id: taxon_id, product_id: product_ids).delete_all
          end

          classifications_params = taxon_ids.flat_map do |taxon_id|
            position = 0
            existing_product_ids = PallasTrade::Classification.where(taxon_id: taxon_id).pluck(:product_id)

            existing_product_ids.map do |product_id|
              {
                taxon_id: taxon_id,
                product_id: product_id,
                position: (position += 1),
                created_at: Time.current,
                updated_at: Time.current
              }
            end
          end

          if classifications_params.any?
            opts = {}
            opts[:unique_by] = :index_PALLASTRADE_products_taxons_on_product_id_and_taxon_id unless mysql_adapter?

            PallasTrade::Classification.upsert_all(
              classifications_params,
              **opts
            )
          end
        end

        # update counter caches
        taxon_ids.each { |id| PallasTrade::Taxon.reset_counters(id, :classifications) }
        product_ids.each { |id| PallasTrade::Product.reset_counters(id, :classifications) }
        # Recompute the descendant-inclusive products_count for the taxons and
        # their ancestors (delete_all skips Classification callbacks).
        PallasTrade::Taxon.recalculate_products_count(taxon_ids)

        # clear cache & index products
        PallasTrade::Product.where(id: product_ids).touch_all
        products.each(&:enqueue_search_index)

        PallasTrade::Taxon.where(id: taxon_ids).touch_all
        PallasTrade::Taxons::TouchFeaturedSections.call(taxon_ids: taxon_ids) if defined?(PallasTrade::Taxons::TouchFeaturedSections)

        success(true)
      end

      private

      def mysql_adapter?
        ActiveRecord::Base.connection.adapter_name.downcase.include?('mysql')
      end
    end
  end
end
