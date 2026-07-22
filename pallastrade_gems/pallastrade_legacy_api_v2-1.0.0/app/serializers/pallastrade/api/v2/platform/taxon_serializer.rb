module PallasTrade
  module Api
    module V2
      module Platform
        class TaxonSerializer < BaseSerializer
          include ResourceSerializerConcern

          attributes :pretty_name, :seo_title

          attribute :description do |taxon|
            taxon.description.to_plain_text
          end

          attribute :header_url do |taxon|
            url_helpers.cdn_image_url(taxon.image.attachment) if taxon.image.present? && taxon.image.attached?
          end

          attribute :is_root do |taxon|
            taxon.root?
          end

          attribute :is_child do |taxon|
            taxon.child?
          end

          attribute :is_leaf do |taxon|
            taxon.leaf?
          end

          belongs_to :parent,   record_type: :taxon, serializer: PallasTrade.api.platform_taxon_serializer
          belongs_to :taxonomy, record_type: :taxonomy, serializer: PallasTrade.api.platform_taxonomy_serializer

          has_many   :children, record_type: :taxon, serializer: PallasTrade.api.platform_taxon_serializer
          has_many   :products, record_type: :product,
                                serializer: PallasTrade.api.platform_product_serializer,
                                if: proc { |_taxon, params| params && params[:include_products] == true }
        end
      end
    end
  end
end
