# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      # Base output schema for capabilities.
      # Subclass and define expected output structure and validation.
      class BaseOutputSchema
        def self.schema
          { type: 'object' }
        end

        def self.valid?(output)
          new(output).valid?
        end

        def initialize(output)
          @output = output || {}
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
          add_error(key, 'is required') unless @output.key?(key.to_s) || @output.key?(key.to_sym)
        end
      end
    end
  end
end
