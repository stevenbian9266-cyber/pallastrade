# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      # Base input schema for capabilities.
      # Subclass and define validation rules for each capability.
      class BaseInputSchema
        def self.valid?(input)
          new(input).valid?
        end

        def initialize(input)
          @input = input || {}
          @errors = []
        end

        def valid?
          validate!
          @errors.empty?
        end

        def errors
          @errors
        end

        private

        def validate!
          # Override in subclasses
        end

        def add_error(field, message)
          @errors << { field: field, message: message }
        end

        def required_field(key)
          add_error(key, 'is required') unless @input.key?(key.to_s) || @input.key?(key.to_sym)
        end
      end
    end
  end
end
