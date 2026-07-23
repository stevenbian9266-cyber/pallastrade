# frozen_string_literal: true

module PallasTradeDevTools
  VERSION = '0.6.3'

  # Returns the version of the currently loaded PallasTradeDevTools as a
  # <tt>Gem::Version</tt>.
  def gem_version
    Gem::Version.new(VERSION)
  end
end
