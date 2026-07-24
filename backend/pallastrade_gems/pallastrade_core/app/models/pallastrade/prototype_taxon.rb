module PallasTrade
  class PrototypeTaxon < PallasTrade.base_class
    belongs_to :taxon, class_name: 'PallasTrade::Taxon'
    belongs_to :prototype, class_name: 'PallasTrade::Prototype'

    validates :prototype, :taxon, presence: true
    validates :prototype_id, uniqueness: { scope: :taxon_id }
  end
end
