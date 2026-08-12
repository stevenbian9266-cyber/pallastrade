require 'pallastrade/core'
require 'pagy'
require 'alba'
require 'oj'
require 'typelizer'
require 'typelizer/proc_resource_resolution'

module PallasTrade
  module Api
  end

  # API dependencies accessor for cleaner access to API dependencies
  #
  # @example Getting a dependency (returns resolved class)
  #   PallasTrade.api.product_serializer
  #
  # @example Setting a dependency
  #   PallasTrade.api.product_serializer = MyApp::ProductSerializer
  #
  # @return [PallasTrade::ApiDependenciesAccessor] the API dependencies accessor
  def self.api
    @api_accessor ||= ApiDependenciesAccessor.new
  end

  class ApiDependenciesAccessor
    def method_missing(method_name, *args, &block)
      base_name = method_name.to_s.chomp('=').to_sym

      return super unless api_dependency?(base_name)

      if method_name.to_s.end_with?('=')
        PallasTrade::Api::Dependencies.send(method_name, args.first)
      else
        # Returns resolved class
        PallasTrade::Api::Dependencies.send("#{method_name}_class")
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      base_name = method_name.to_s.chomp('=').to_sym
      api_dependency?(base_name) || super
    end

    # Direct access to the raw API dependencies object
    def dependencies
      PallasTrade::Api::Dependencies
    end

    private

    def api_dependency?(name)
      return false unless defined?(PallasTrade::Api::Dependencies)

      # Check registered API V3 dependencies
      PallasTrade::Api::Dependencies.class::INJECTION_POINTS.include?(name)
    end
  end
end

require 'pallastrade/api/engine'
require 'pallastrade/api/turnstile'
