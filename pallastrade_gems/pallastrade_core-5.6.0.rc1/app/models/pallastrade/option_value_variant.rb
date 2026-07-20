module PallasTrade
  class OptionValueVariant < PallasTrade.base_class
    belongs_to :option_value, class_name: 'PallasTrade::OptionValue'
    belongs_to :variant, touch: true, class_name: 'PallasTrade::Variant'

    validates :option_value, :variant, presence: true
    validates :option_value_id, uniqueness: { scope: :variant_id }

    scope :for_option_types, lambda { |option_types|
      joins(:option_value).merge(PallasTrade::OptionValue.where(option_type: option_types))
    }
  end
end
