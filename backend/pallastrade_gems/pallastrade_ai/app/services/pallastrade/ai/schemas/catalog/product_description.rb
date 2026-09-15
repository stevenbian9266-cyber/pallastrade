# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      module Catalog
        # `catalog.product_description` — product copy generation
        # (PRD-20260915-catalog-batch-e1-ai-copilot FR-001/FR-002).
        #
        # Generate → Preview → Accept → Save: this capability only produces
        # text. Nothing here (or in its handler) writes to the product.
        module ProductDescription
          class Input < PallasTrade::AI::Schemas::BaseInputSchema
            MODES = %w[generate rewrite].freeze

            private

            def validate!
              required_field(:product_name)
              required_field(:locale)

              mode = @input[:mode] || @input['mode'] || 'generate'
              add_error(:mode, "must be one of #{MODES.join(', ')}") unless MODES.include?(mode.to_s)
            end
          end

          class Output < PallasTrade::AI::Schemas::BaseOutputSchema
            def self.schema
              {
                type: 'object',
                properties: {
                  text: { type: 'string' }
                },
                required: %w[text]
              }
            end

            private

            def validate!
              required_field(:text)
              value = @output[:text] || @output['text']
              add_error(:text, 'must not be blank') if value.respond_to?(:blank?) && value.blank?
            end
          end

          # Handler contract (`build_messages` / `apply_result`) — the gateway
          # invokes business services directly, but keeping the handler aligned
          # means the capability can also be driven by the async executor.
          class Handler
            # The prompt itself is assembled by
            # `PallasTrade::AI::Catalog::ProductCopy` (it owns the product
            # facts); this stays a contract-compatible placeholder so the
            # capability can also be driven by the async executor.
            def self.build_messages(_run)
              [{ role: 'user', content: 'Generate product copy from the supplied product facts.' }]
            end

            def self.apply_result(run, response)
              output = response.structured_output || {}
              run.artifacts.create!(
                kind: 'structured_output',
                payload: { text: output['text'] || output[:text] || response.text },
                schema_version: '1.0.0'
              )
            end
          end
        end
      end
    end
  end
end
