module PallasTrade
  module Products
    class TouchTaxonsJob < ::PallasTrade::BaseJob
      queue_as PallasTrade.queues.taxons

      def perform(taxon_ids, taxonomy_ids)
        PallasTrade::Taxon.where(id: taxon_ids).update_all(updated_at: Time.current)
        PallasTrade::Taxonomy.where(id: taxonomy_ids).update_all(updated_at: Time.current)
      end
    end
  end
end
