# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      # Test echo capability 鈥?only available in test environment.
      # Echoes back the input as structured output for contract testing.
      #
      # This is NOT registered in production. Use for testing the Gateway,
      # Adapters, and Run lifecycle without calling external providers.
      module TestEcho
        # Input: accepts any string message.
        class Input < BaseInputSchema
          private

          def validate!
            required_field(:message)
          end
        end

        # Output: echoes the message back.
        class Output < BaseOutputSchema
          def self.schema
            {
              type: 'object',
              properties: {
                echo: { type: 'string' },
                received_at: { type: 'string' }
              },
              required: %w[echo received_at]
            }
          end

          private

          def validate!
            required_field(:echo)
            required_field(:received_at)
          end
        end

        # Handler: processes test echo requests.
        # In a real capability, this would construct prompts and process results.
        class Handler
          # Build messages for the AI model.
          def self.build_messages(run)
            [
              { role: 'user', content: 'Echo back: "Hello from PallasTrade AI test!"' }
            ]
          end

          # Apply the AI response to the business resource.
          def self.apply_result(run, response)
            run.artifacts.create!(
              kind: 'structured_output',
              payload: {
                echo: response.structured_output&.dig('echo') || response.text,
                received_at: Time.current.iso8601
              },
              schema_version: '1.0.0'
            )
          end
        end
      end
    end
  end
end
