module PallasTrade
  class StoreCreditType < PallasTrade.base_class
    has_prefix_id :sctype

    DEFAULT_TYPE_NAME = 'Expiring'.freeze
    has_many :store_credits, class_name: 'PallasTrade::StoreCredit', foreign_key: 'type_id'

    validates :name, presence: true
  end
end
