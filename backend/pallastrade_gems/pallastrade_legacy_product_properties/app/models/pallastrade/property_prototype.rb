module PallasTrade
  class PropertyPrototype < PallasTrade.base_class
    belongs_to :prototype, class_name: 'PallasTrade::Prototype'
    belongs_to :property, class_name: 'PallasTrade::Property'

    validates :prototype, :property, presence: true
    validates :prototype_id, uniqueness: { scope: :property_id }
  end
end
