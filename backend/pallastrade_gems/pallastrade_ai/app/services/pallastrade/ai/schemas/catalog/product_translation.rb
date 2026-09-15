# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      module Catalog
        # `catalog.product_translation` — missing-field translation
        # (PRD-20260915-catalog-batch-e2-ai-translate-missing FR-001/FR-002).
        #
        # Generate → Preview → Accept → Save: this capability only produces
        # translated text. Nothing here (or in its handler) writes to the
        # product or to its translations.
        module ProductTranslation
          # Fields this capability may translate. `slug` is deliberately absent:
          # rewriting it changes storefront URLs and belongs to the redirects
          # workflow (PRD FR-009).
          FIELDS = %w[name description meta_title meta_description].freeze

          class Input < PallasTrade::AI::Schemas::BaseInputSchema
            private

            def validate!
              required_field(:product_name)
              required_field(:source_locale)
              required_field(:target_locale)

              add_error(:fields, 'must contain at least one translatable field') if requested_fields.empty?
              if source_locale.present? && source_locale == target_locale
                add_error(:target_locale, 'must differ from source_locale')
              end
            end

            def source_locale
              (@input[:source_locale] || @input['source_locale']).to_s
            end

            def target_locale
              (@input[:target_locale] || @input['target_locale']).to_s
            end

            # Only the fields this capability owns and that carry a value.
            def requested_fields
              fields = @input[:fields] || @input['fields']
              return [] unless fields.is_a?(Hash)

              fields.select { |key, value| FIELDS.include?(key.to_s) && value.to_s.present? }
            end
          end

          class Output < PallasTrade::AI::Schemas::BaseOutputSchema
            def self.schema
              {
                type: 'object',
                properties: {
                  translations: { type: 'object' }
                },
                required: %w[translations]
              }
            end

            private

            def validate!
              required_field(:translations)
              translations = @output[:translations] || @output['translations']
              return if translations.is_a?(Hash) && translations.any?

              add_error(:translations, 'must be a non-empty object keyed by field name')
            end
          end

          # Handler contract (`build_messages` / `apply_result`) — the gateway
          # invokes business services directly, but keeping the handler aligned
          # means the capability can also be driven by the async executor.
          class Handler
            # The prompt itself is assembled by
            # `PallasTrade::AI::Catalog::ProductTranslation` (it owns the product
            # facts); this stays a contract-compatible placeholder.
            def self.build_messages(_run)
              [{ role: 'user', content: 'Translate the supplied product fields into the requested locale.' }]
            end

            def self.apply_result(run, response)
              output = response.structured_output || {}
              run.artifacts.create!(
                kind: 'structured_output',
                payload: { translations: output['translations'] || output[:translations] || {} },
                schema_version: '1.0.0'
              )
            end
          end
        end
      end
    end
  end
end
