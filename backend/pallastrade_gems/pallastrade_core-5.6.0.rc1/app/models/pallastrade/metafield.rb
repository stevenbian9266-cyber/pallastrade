module PallasTrade
  class Metafield < PallasTrade.base_class
    # Map of API-facing tokens to Ruby STI class names. The wire format is the
    # token (`short_text`); the database column stores the class name. Reads
    # translate to the token via `field_type`; writes accept either form.
    # Plugin-defined types fall through to the raw class name until 6.0 when a
    # registration API lands.
    TYPE_TOKENS = {
      'short_text' => 'PallasTrade::Metafields::ShortText',
      'long_text'  => 'PallasTrade::Metafields::LongText',
      'rich_text'  => 'PallasTrade::Metafields::RichText',
      'number'     => 'PallasTrade::Metafields::Number',
      'boolean'    => 'PallasTrade::Metafields::Boolean',
      'json'       => 'PallasTrade::Metafields::Json'
    }.freeze
    TYPE_CLASS_TO_TOKEN = TYPE_TOKENS.invert.freeze

    # Array form consumed by serializers via
    # `typelize field_type: PallasTrade::Metafield::FIELD_TYPE_TOKENS`. Typelizer
    # emits a string-literal union in TypeScript and `{type: string, enum: […]}`
    # in OpenAPI (string-array form was added in typelizer 0.10.0).
    FIELD_TYPE_TOKENS = TYPE_TOKENS.keys.freeze

    has_prefix_id :cf

    #
    # Associations
    #
    belongs_to :resource, polymorphic: true, touch: true
    belongs_to :metafield_definition, class_name: 'PallasTrade::MetafieldDefinition'

    #
    # API naming bridge — internal column rename lands in 6.0
    #
    alias_attribute :custom_field_definition_id, :metafield_definition_id

    # API-facing form of the STI `type` column. Returns the token
    # (`short_text`) when the row's type is a registered built-in; falls
    # through to the raw class name for plugin types.
    #
    # `self[:type]` reads the raw column to bypass AR's STI reader (which
    # returns the resolved class constant, not a string).
    def field_type
      TYPE_CLASS_TO_TOKEN[self[:type]] || self[:type]
    end

    #
    # Delegations
    #
    delegate :key, :full_key, :name, :label, :display_on, to: :metafield_definition, allow_nil: true

    #
    # Callbacks
    #
    before_validation :set_type_from_metafield_definition, on: :create

    #
    # Validations
    #
    validates :metafield_definition, :type, :resource, :value, presence: true
    validates :metafield_definition_id, uniqueness: { scope: [:resource_type, :resource_id] }
    validate :type_must_match_metafield_definition

    #
    # Scopes
    #
    scope :available_on_front_end, -> { joins(:metafield_definition).merge(PallasTrade::MetafieldDefinition.available_on_front_end) }
    scope :available_on_back_end, -> { joins(:metafield_definition).merge(PallasTrade::MetafieldDefinition.available_on_back_end) }
    scope :with_key, ->(namespace, key) { joins(:metafield_definition).where(pallastrade_metafield_definitions: { namespace: namespace, key: key }) }

    def serialize_value
      value
    end

    def csv_value
      value.to_s
    end

    private

    def set_type_from_metafield_definition
      return if metafield_definition.blank?

      self.type ||= metafield_definition.metafield_type
    end

    def type_must_match_metafield_definition
      return if metafield_definition.blank?

      errors.add(:type, 'must match metafield definition') unless type == metafield_definition.metafield_type
    end
  end
end
