class PallasTrade::Preference < PallasTrade.base_class
  if Rails::VERSION::STRING >= '7.1.0'
    serialize :value, coder: YAML
  else
    serialize :value
  end

  validates :key, presence: true,
                  uniqueness: { case_sensitive: false, allow_blank: true, scope: pallastrade_base_uniqueness_scope }

  if defined?(PallasTrade::Security::Preferences)
    include PallasTrade::Security::Preferences
  end
end
