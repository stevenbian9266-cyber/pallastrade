# frozen_string_literal: true

module PallasTrade
  module AI
    module Schemas
      module Catalog
        # `catalog.health_fix_suggestion` — Catalog Health remediation advice
        # (PRD-20260916-catalog-batch-e3-ai-fix-suggestion FR-001/FR-002).
        #
        # Advice only: the capability produces a plan for the merchant and has no
        # write path. `entry` values are limited to the admin surfaces that
        # actually exist, so a suggestion can never point at an invented action.
        module HealthFixSuggestion
          SCOPES = %w[catalog product].freeze

          # Where a step can send the merchant. Kept in sync with
          # `PallasTrade::AI::Catalog::HealthFixSuggestion::ENTRIES`.
          ENTRIES = %w[
            product_edit_ai
            translations_drawer
            product_media
            variant_inventory
            redirects
            publishing
          ].freeze

          class Input < PallasTrade::AI::Schemas::BaseInputSchema
            private

            def validate!
              add_error(:scope, "must be one of #{SCOPES.join(', ')}") unless SCOPES.include?(scope)

              if scope == 'product'
                required_field(:product_name)
                add_error(:issue_keys, 'must list at least one catalog health issue') if issue_keys.empty?
                add_error(:unknown_issue_keys, 'must be catalog health issues') unless unknown_issue_keys.empty?
              else
                required_field(:issue_key)
                add_error(:issue_key, 'must be a known catalog health issue') unless known_issue_key?
                add_error(:count, 'is required') if @input[:count].nil? && @input['count'].nil?
              end
            end

            def scope
              (@input[:scope] || @input['scope'] || 'catalog').to_s
            end

            def issue_key
              (@input[:issue_key] || @input['issue_key']).to_s
            end

            def issue_keys
              Array(@input[:issue_keys] || @input['issue_keys']).map(&:to_s)
            end

            def known_issue_key?
              PallasTrade::CatalogHealth::Issues.valid?(issue_key)
            end

            def unknown_issue_keys
              issue_keys.reject { |key| PallasTrade::CatalogHealth::Issues.valid?(key) }
            end
          end

          class Output < PallasTrade::AI::Schemas::BaseOutputSchema
            def self.schema
              {
                type: 'object',
                properties: {
                  summary: { type: 'string' },
                  steps: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: {
                        title: { type: 'string' },
                        detail: { type: 'string' },
                        entry: { type: 'string', enum: ENTRIES }
                      },
                      required: %w[title]
                    }
                  }
                },
                required: %w[summary steps]
              }
            end

            private

            def validate!
              required_field(:summary)
              steps = @output[:steps] || @output['steps']
              return add_error(:steps, 'must be a non-empty array') unless steps.is_a?(Array) && steps.any?

              steps.each_with_index do |step, index|
                title = step.is_a?(Hash) ? (step['title'] || step[:title]) : nil
                add_error(:steps, "step #{index + 1} needs a title") if title.to_s.strip.blank?
              end
            end
          end

          # Handler contract (`build_messages` / `apply_result`) — the gateway
          # invokes the business service directly, but keeping the handler aligned
          # means the capability can also be driven by the async executor.
          class Handler
            def self.build_messages(_run)
              [{ role: 'user', content: 'Suggest how to fix the reported catalog health issues.' }]
            end

            def self.apply_result(run, response)
              output = response.structured_output || {}
              run.artifacts.create!(
                kind: 'structured_output',
                payload: {
                  summary: output['summary'] || output[:summary],
                  steps: output['steps'] || output[:steps] || []
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
