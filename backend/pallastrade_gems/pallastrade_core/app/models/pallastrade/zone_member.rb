module PallasTrade
  class ZoneMember < PallasTrade.base_class
    belongs_to :zone, class_name: 'PallasTrade::Zone', counter_cache: true, inverse_of: :zone_members
    belongs_to :zoneable, polymorphic: true

    validates :zone, :zoneable, presence: true
    validates :zoneable_id, uniqueness: { scope: pallastrade_base_uniqueness_scope + [:zone_id, :zoneable_type] }

    scope :defunct_without_kind, ->(kind) do
      where('zoneable_id IS NULL OR zoneable_type != ?', "PallasTrade::#{kind.classify}")
    end
  end
end
