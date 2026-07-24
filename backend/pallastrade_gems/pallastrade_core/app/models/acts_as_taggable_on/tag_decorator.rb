module ActsAsTaggableOn
  module TagDecorator
    def self.prepended(base)
      require_relative '../concerns/pallastrade/ransackable_attributes'
      base.include ::PallasTrade::RansackableAttributes
      base.whitelisted_ransackable_attributes = %w[id name]
    end
  end

  Tag.prepend(TagDecorator)
end
