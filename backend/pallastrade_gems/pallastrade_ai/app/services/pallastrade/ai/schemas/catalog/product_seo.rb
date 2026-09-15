# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      module Catalog
        # `catalog.product_seo` — meta title + meta description generation
        # (PRD-20260915-catalog-batch-e1-ai-copilot FR-001/FR-004).
        module ProductSeo
          class Input < PallasTrade::AI::Schemas::BaseInputSchema
            private

            def validate!
              required_field(:product_name)
              required_field(:locale)
            end
          end

          class Output < PallasTrade::AI::Schemas::BaseOutputSchema
            MAX_TITLE = 70
            MAX_DESCRIPTION = 200

            def self.schema
              {
                type: 'object',
                properties: {
                  meta_title: { type: 'string' },
                  meta_description: { type: 'string' }
                },
                required: %w[meta_title meta_description]
              }
            end

            private

            def validate!
              required_field(:meta_title)
              required_field(:meta_description)

              title = @output[:meta_title] || @output['meta_title']
              description = @output[:meta_description] || @output['meta_description']

              add_error(:meta_title, 'must not be blank') if title.respond_to?(:blank?) && title.blank?
              if description.respond_to?(:blank?) && description.blank?
                add_error(:meta_description, 'must not be blank')
              end
              add_error(:meta_title, "must be at most #{MAX_TITLE} characters") if title.to_s.length > MAX_TITLE
              if description.to_s.length > MAX_DESCRIPTION
                add_error(:meta_description, "must be at most #{MAX_DESCRIPTION} characters")
              end
            end
          end

          class Handler
            def self.build_messages(_run)
              [{ role: 'user', content: 'Generate the SEO meta fields from the supplied product facts.' }]
            end

            def self.apply_result(run, response)
              output = response.structured_output || {}
              run.artifacts.create!(
                kind: 'structured_output',
                payload: {
                  meta_title: output['meta_title'] || output[:meta_title],
                  meta_description: output['meta_description'] || output[:meta_description]
                },
                schema_version: '1.0.0'
              )
            end
          end
        end
      end
    end
  end
end
