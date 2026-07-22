module PallasTrade
  module PrototypeDecorator
    def self.prepended(base)
      base.has_many :property_prototypes, class_name: 'PallasTrade::PropertyPrototype'
      base.has_many :properties, through: :property_prototypes, class_name: 'PallasTrade::Property'
    end
  end
end

PallasTrade::Prototype.prepend(PallasTrade::PrototypeDecorator)
