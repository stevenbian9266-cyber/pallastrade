# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalog
      # Product translation assistant
      # (PRD-20260915-catalog-batch-e2-ai-translate-missing FR-002/FR-005/FR-007).
      #
      # Translates **only the fields that are still empty in the target locale**
      # (never overwrites an existing translation), using the store's default
      # locale as the source. The result goes back to the translations drawer,
      # where the merchant reviews it (Generate → Preview → Accept → Save) and
      # the drawer's own form performs the save — this service never writes.
      class ProductTranslation
        CAPABILITY = 'catalog.product_translation'

        # `slug` is out of scope: rewriting it changes storefront URLs and must
        # go through the redirects workflow (PRD FR-009).
        TRANSLATABLE_FIELDS = %i[name description meta_title meta_description].freeze

        # @!attribute [r] status
        #   @return [Symbol] :success, the gateway's failure status, or :rejected
        #     when there was nothing to translate / the locale is unsupported
        # @!attribute [r] translations
        #   @return [Hash{String=>String}] field name => translated text
        # @!attribute [r] target_locale
        #   @return [String] locale the translations belong to
        # @!attribute [r] missing_fields
        #   @return [Array<String>] fields the request asked the model to fill
        # @!attribute [r] run_id
        #   @return [Integer, nil] `PallasTrade::AI::Run` id when a run was created
        # @!attribute [r] error_code
        #   @return [String, nil] stable reason code for the UI
        Result = Struct.new(:status, :translations, :target_locale, :missing_fields, :run_id, :error_code,
                            keyword_init: true) do
          def success?
            status.to_sym == :success
          end
        end

        # @param product [PallasTrade::Product]
        # @param target_locale [String] e.g. 'zh-CN'
        # @return [Result]
        def self.generate_missing(product:, actor:, target_locale:)
          new(product: product, actor: actor).generate_missing(target_locale: target_locale)
        end

        # Fields with no value in +target_locale+ yet.
        # @return [Array<Symbol>]
        def self.missing_fields(product, target_locale:)
          new(product: product, actor: nil).missing_fields(target_locale)
        end

        # @param product [PallasTrade::Product]
        # @param actor [PallasTrade::AdminUser, nil]
        def initialize(product:, actor:)
          @product = product
          @actor = actor
        end

        attr_reader :product, :actor

        # Reads with `fallback: false` on purpose: inside a request Mobility is
        # configured to fall back to the store's default locale, which would make
        # a missing translation look translated (see `pallastrade-i18n`).
        #
        # @param target_locale [String]
        # @return [Array<Symbol>]
        def missing_fields(target_locale)
          TRANSLATABLE_FIELDS.select { |field| blank_in_locale?(field, target_locale) }
        end

        # @param target_locale [String]
        # @return [Result]
        def generate_missing(target_locale:)
          target = resolve_locale(target_locale)

          return rejected(target_locale.to_s, 'unsupported_locale') if target.nil?

          fields = missing_fields(target)
          # Nothing to fill: answer without spending a model call or writing a Run.
          return rejected(target, 'no_missing_fields') if fields.empty?

          source = source_locale
          result = gateway_call(target_locale: target, source_locale: source, fields: fields)

          Result.new(
            status: result.status,
            translations: normalize_translations(structured_output(result)['translations'], fields),
            target_locale: target,
            missing_fields: fields.map(&:to_s),
            run_id: result.run&.id,
            error_code: result.error_code&.to_s
          )
        end

        private

        def rejected(target_locale, error_code)
          Result.new(status: :rejected, translations: {}, target_locale: target_locale,
                     missing_fields: [], error_code: error_code)
        end

        def gateway_call(target_locale:, source_locale:, fields:)
          PallasTrade::AI::Gateway.call(
            capability: CAPABILITY,
            store: product.store,
            actor: actor,
            input: {
              product_name: product.name,
              source_locale: source_locale,
              target_locale: target_locale,
              fields: source_values(fields, source_locale),
              messages: [{ role: 'user', content: translation_prompt(target_locale, fields, source_locale) }],
              system_instructions: system_instructions
            },
            resource: product
          )
        end

        def structured_output(result)
          return {} unless result.respond_to?(:output)

          output = result.output
          raw = output.respond_to?(:structured_output) ? output.structured_output : output
          raw.is_a?(Hash) ? raw : {}
        end

        # Keeps only the fields that were asked for, as trimmed plain text.
        def normalize_translations(raw, fields)
          return {} unless raw.is_a?(Hash)

          allowed = fields.map(&:to_s)
          raw.each_with_object({}) do |(key, value), translations|
            name = key.to_s
            next unless allowed.include?(name)

            text = value.to_s.squish
            translations[name] = text if text.present?
          end
        end

        def blank_in_locale?(field, locale)
          product.get_field_with_locale(locale, field, fallback: false).to_s.strip.blank?
        end

        def source_values(fields, source_locale)
          fields.index_with { |field| product.get_field_with_locale(source_locale, field, fallback: true).to_s }
        end

        # The translations drawer works with normalized field suffixes
        # (`name_zh_cn`), while Mobility stores and reads the locale code
        # (`zh-CN`). Map the suffix the drawer sends back to a code the store
        # actually supports; nil means "not a locale of this store".
        def resolve_locale(locale)
          raw = locale.to_s.strip
          return nil if raw.blank?

          supported = product.store&.supported_locales_list.to_a
          return raw if supported.empty?

          supported.find { |code| code.to_s.casecmp?(raw) } ||
            supported.find { |code| normalized_locale(code) == normalized_locale(raw) }
        end

        def normalized_locale(locale)
          locale.to_s.downcase.tr('-', '_')
        end

        def source_locale
          product.store&.default_locale.presence || 'en'
        end

        def system_instructions
          <<~PROMPT.squish
            You are a native-level e-commerce translator working on a product catalog.
            Translate only the fields you are given, keeping the meaning, tone and every
            factual detail intact — brand names, model numbers, sizes and units stay as they
            are. Never invent specifications, certifications, prices or availability, and
            never leave a field empty. Answer in plain text (no markdown, no HTML) with a
            JSON object holding a single "translations" object that uses the same field keys
            you were given.
          PROMPT
        end

        def translation_prompt(target_locale, fields, source_locale)
          facts = fields.map { |field| "#{field}: #{product.get_field_with_locale(source_locale, field, fallback: true)}" }
          <<~PROMPT.squish
            Translate these product fields from #{source_locale} into #{target_locale}:
            #{facts.join("\n")}
          PROMPT
        end
      end
    end
  end
end
