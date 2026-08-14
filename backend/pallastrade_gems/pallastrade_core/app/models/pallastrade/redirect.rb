# frozen_string_literal: true

module PallasTrade
  class Redirect < PallasTrade.base_class
    has_prefix_id :red

    include PallasTrade::SingleStoreResource

    belongs_to :store, class_name: 'PallasTrade::Store'

    scope :active, -> { where(active: true) }

    validates :store, :from_path, :to_path, presence: true
    validates :from_path, uniqueness: { scope: [:store_id, *pallastrade_base_uniqueness_scope] }
    validate :to_path_must_be_internal

    before_validation :normalize_paths

    # Normalize a path: ensure a leading slash and strip trailing slash (except
    # root "/"). For +from_path+ a leading origin is stripped too (so pasting a
    # full URL works); for +to_path+ the origin is preserved so external URLs
    # are left untouched and caught by #to_path_must_be_internal.
    # @param path [String, nil]
    # @param strip_origin [Boolean]
    # @return [String]
    def self.normalize_path(path, strip_origin: true)
      p = path.to_s.strip
      p = p.sub(%r{\Ahttps?://[^/]+}, '') if strip_origin
      return p if p.match?(%r{\Ahttps?://})

      p = "/#{p}" unless p.start_with?('/')
      p = p.chomp('/') unless p == '/'
      p
    end

    private

    def normalize_paths
      self.from_path = self.class.normalize_path(from_path, strip_origin: true) if from_path.present?
      self.to_path = self.class.normalize_path(to_path, strip_origin: false) if to_path.present?
    end

    def to_path_must_be_internal
      errors.add(:to_path, :must_be_internal) if to_path.present? && to_path.match?(%r{\Ahttps?://})
    end
  end
end
