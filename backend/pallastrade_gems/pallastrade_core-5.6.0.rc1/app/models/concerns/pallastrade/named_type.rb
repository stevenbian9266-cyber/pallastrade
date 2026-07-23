module PallasTrade
  module NamedType
    extend ActiveSupport::Concern

    included do
      scope :active, -> { where(active: true) }
      default_scope { order(name: :asc) }

      include PallasTrade::UniqueName
    end
  end
end
