require 'pallastrade/admin'

module PallasTrade
  def self.admin_path
    PallasTrade::Admin::RuntimeConfig[:admin_path]
  end

  # Used to configure admin_path for Spree
  #
  # Example:
  #
  # write the following line in `config/initializers/PallasTrade.rb`
  #   PallasTrade.admin_path = '/custom-path'

  def self.admin_path=(path)
    PallasTrade::Admin::RuntimeConfig[:admin_path] = path
  end
end
