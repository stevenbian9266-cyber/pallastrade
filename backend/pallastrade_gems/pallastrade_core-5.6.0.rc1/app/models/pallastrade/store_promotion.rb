module PallasTrade
  # Legacy join between Store and Promotion. Superseded by the single-store
  # +Promotion#store+ FK in 5.6; retained only so the +pallastrade_multi_store+
  # extension can restore +has_many :stores+ and so the backfill task can read
  # historic attachments. Dropped in 6.0.
  class StorePromotion < PallasTrade.base_class
    self.table_name = 'pallastrade_promotions_stores'

    belongs_to :store, class_name: 'PallasTrade::Store', touch: true
    belongs_to :promotion, class_name: 'PallasTrade::Promotion', touch: true

    validates :store, :promotion, presence: true
    validates :store_id, uniqueness: { scope: :promotion_id }
  end
end
