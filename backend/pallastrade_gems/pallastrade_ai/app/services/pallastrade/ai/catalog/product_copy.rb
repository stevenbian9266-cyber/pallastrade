# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalog
      # Product copy assistant (PRD-20260915-catalog-batch-e1-ai-copilot
      # FR-002/FR-005/FR-007).
      #
      # Assembles the product facts, calls the AI Gateway and returns the draft.
      # It never writes to the product: the merchant reviews the draft in the
      # admin (Generate → Preview → Accept → Save) and the regular product form
      # performs the save. Each call leaves a `PallasTrade::AI::Run` behind for
      # audit and cost tracking, and only the input digest is persisted (never
      # the prompt itself).
      class ProductCopy
        DESCRIPTION_CAPABILITY = 'catalog.product_description'
        SEO_CAPABILITY = 'catalog.product_seo'
        MODES = %w[generate rewrite].freeze

        # @!attribute [r] status
        #   @return [Symbol] :success or the failure status from the gateway
        # @!attribute [r] text
        #   @return [String, nil] description draft
        # @!attribute [r] meta_title
        #   @return [String, nil]
        # @!attribute [r] meta_description
        #   @return [String, nil]
        # @!attribute [r] run_id
        #   @return [Integer, nil] `PallasTrade::AI::Run` id when a run was created
        # @!attribute [r] error_code
        #   @return [String, nil] stable reason code for the UI
        Result = Struct.new(:status, :text, :meta_title, :meta_description, :run_id, :error_code,
                            keyword_init: true) do
          def success?
            status.to_sym == :success
          end
        end

        def self.generate_description(product:, actor:, mode: 'generate')
          new(product: product, actor: actor).generate_description(mode: mode)
        end

        def self.generate_seo(product:, actor:)
          new(product: product, actor: actor).generate_seo
        end

        # @param product [PallasTrade::Product]
        # @param actor [PallasTrade::AdminUser]
        def initialize(product:, actor:)
          @product = product
          @actor = actor
        end

        attr_reader :product, :actor

        # @return [Result]
        def generate_description(mode: 'generate')
          mode = MODES.include?(mode.to_s) ? mode.to_s : 'generate'

          result = gateway_call(
            capability: DESCRIPTION_CAPABILITY,
            messages: [{ role: 'user', content: description_prompt(mode) }],
            system_instructions: description_system_instructions,
            input: description_input(mode)
          )

          output = structured_output(result)
          Result.new(
            status: result.status,
            text: output['text'] || output[:text],
            run_id: result.run&.id,
            error_code: result.error_code&.to_s
          )
        end

        # @return [Result]
        def generate_seo
          result = gateway_call(
            capability: SEO_CAPABILITY,
            messages: [{ role: 'user', content: seo_prompt }],
            system_instructions: seo_system_instructions,
            input: seo_input
          )

          output = structured_output(result)
          Result.new(
            status: result.status,
            meta_title: output['meta_title'] || output[:meta_title],
            meta_description: output['meta_description'] || output[:meta_description],
            run_id: result.run&.id,
            error_code: result.error_code&.to_s
          )
        end

        private

        def gateway_call(capability:, messages:, system_instructions:, input:)
          PallasTrade::AI::Gateway.call(
            capability: capability,
            store: product.store,
            actor: actor,
            input: input.merge(messages: messages, system_instructions: system_instructions),
            resource: product
          )
        end

        def structured_output(result)
          return {} unless result.respond_to?(:output)

          output = result.output
          raw = output.respond_to?(:structured_output) ? output.structured_output : output
          raw.is_a?(Hash) ? raw : {}
        end

        def description_input(mode)
          {
            product_name: product.name,
            category: category_names.join(', '),
            attributes: attribute_summary,
            existing_description: mode == 'rewrite' ? existing_description : nil,
            locale: locale,
            mode: mode
          }
        end

        def seo_input
          {
            product_name: product.name,
            category: category_names.join(', '),
            description: existing_description,
            locale: locale
          }
        end

        def description_system_instructions
          <<~PROMPT.squish
            You are a product copywriter for an e-commerce catalog. Write in #{locale_name} for shoppers.
            Return a JSON object with a single "text" field containing plain text (no markdown headings,
            no HTML). Never invent specifications, certifications, prices or availability that are not
            present in the facts you were given.
          PROMPT
        end

        def seo_system_instructions
          <<~PROMPT.squish
            You write search engine listing copy in #{locale_name} for an e-commerce catalog.
            Return a JSON object with "meta_title" (at most 60 characters) and "meta_description"
            (at most 155 characters). Do not invent specifications or claims that are not present in
            the facts you were given, and do not repeat the store name.
          PROMPT
        end

        def description_prompt(mode)
          action = mode == 'rewrite' ? 'Rewrite the description' : 'Write a product description'
          <<~PROMPT.squish
            #{action} for the following product. Facts:
            name: #{product.name}
            category: #{category_names.join(', ')}
            attributes: #{attribute_summary}
            current description: #{existing_description.presence || '(none)'}
            Write 40-120 words of plain text.
          PROMPT
        end

        def seo_prompt
          <<~PROMPT.squish
            Write the search engine listing for the following product. Facts:
            name: #{product.name}
            category: #{category_names.join(', ')}
            description: #{existing_description.presence || '(none)'}
          PROMPT
        end

        def category_names
          @category_names ||= product.categories.map(&:name).compact
        end

        def attribute_summary
          names = product.option_types.map(&:name).compact
          skus = product.variants_including_master.filter_map { |variant| variant.sku.presence }
          parts = []
          parts << "options: #{names.join(', ')}" if names.any?
          parts << "skus: #{skus.first(5).join(', ')}" if skus.any?
          parts.presence&.join('; ') || '(none)'
        end

        def existing_description
          product.description.to_s
        end

        def locale
          product.store&.default_locale.presence || 'en'
        end

        def locale_name
          locale
        end
      end
    end
  end
end
