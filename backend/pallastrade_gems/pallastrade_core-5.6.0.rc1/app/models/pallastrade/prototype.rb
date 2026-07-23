module PallasTrade
  class Prototype < PallasTrade.base_class
    has_prefix_id :proto

    include PallasTrade::Metadata

    has_many :option_type_prototypes, class_name: 'PallasTrade::OptionTypePrototype'
    has_many :option_types, through: :option_type_prototypes, class_name: 'PallasTrade::OptionType'

    has_many :prototype_taxons, class_name: 'PallasTrade::PrototypeTaxon'
    has_many :taxons, through: :prototype_taxons, class_name: 'PallasTrade::Taxon'

    validates :name, presence: true
  end
end
