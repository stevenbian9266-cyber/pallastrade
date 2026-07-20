module PallasTrade
  class StateChange < PallasTrade.base_class
    has_prefix_id :sc

    belongs_to :user, class_name: "::#{PallasTrade.user_class}", optional: true
    belongs_to :stateful, polymorphic: true

    def <=>(other)
      created_at <=> other.created_at
    end
  end
end
