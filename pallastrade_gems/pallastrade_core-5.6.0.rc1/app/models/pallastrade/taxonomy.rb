module PallasTrade
  class Taxonomy < PallasTrade.base_class
    has_prefix_id :txnmy  # Spree-specific: taxonomy

    include PallasTrade::TranslatableResource
    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::SingleStoreResource

    TRANSLATABLE_FIELDS = %i[name].freeze
    translates(*TRANSLATABLE_FIELDS, column_fallback: PallasTrade.mobility_column_fallback)

    acts_as_list

    validates :name, presence: true, uniqueness: { case_sensitive: false, scope: :store_id }
    validates :store, presence: true

    has_many :taxons, inverse_of: :taxonomy
    has_one :root, -> { where parent_id: nil }, class_name: 'PallasTrade::Taxon', dependent: :destroy
    belongs_to :store, class_name: 'PallasTrade::Store'

    after_create :set_root
    after_update :set_root_taxon_name

    default_scope { order("#{table_name}.position, #{table_name}.created_at") }

    scope :with_matching_name, ->(name_to_match) do
      value = name_to_match.to_s.strip.downcase

      if PallasTrade.use_translations?
        i18n { name.lower.eq(value) }
      else
        where(arel_table[:name].lower.eq(value))
      end
    end

    self.whitelisted_ransackable_attributes = %w[name]
    self.whitelisted_ransackable_associations = %w[root]

    private

    def set_root
      self.root ||= Taxon.create!(taxonomy_id: id, name: name)
    end

    def set_root_taxon_name
      return unless saved_changes.key?(:name)
      return if name.to_s == root.name.to_s

      root.update(name: name)
    end
  end
end
