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
  #   PallasTrade.api.storefront_coupon_handler.call(order: order, coupon_code: code)
  #
  # @example Setting a dependency
  #   PallasTrade.api.storefront_coupon_handler = MyApp::CouponHandler
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

    # Direct access to raw dependencies object for backwards compatibility
    def dependencies
      PallasTrade::Api::Dependencies
    end

    private

    def api_dependency?(name)
      return false unless defined?(PallasTrade::Api::Dependencies)

      # Check both V3 and dynamically added V2 dependencies
      PallasTrade::Api::Dependencies.class::INJECTION_POINTS.include?(name)
    end
  end
end

require 'pallastrade/api/engine'
