# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalog
      # Catalog Health fix assistant
      # (PRD-20260916-catalog-batch-e3-ai-fix-suggestion FR-002/FR-005/FR-007).
      #
      # Two granularities, both **read-only**:
      #   * worklist level (`.generate` / `issue_key:`) — one catalog health issue
      #     on the Catalog Health page;
      #   * product level (`.generate_for_product`) — every issue a single product
      #     currently hits, for the product form sidebar card.
      #
      # The service samples the same scopes the worklist counts (so the advice and
      # the page can never disagree), turns them into product facts and asks the
      # gateway for an ordered plan. It never writes to the catalog: the merchant
      # performs every change in the surfaces the plan points at.
      class HealthFixSuggestion
        CAPABILITY = 'catalog.health_fix_suggestion'

        # Surfaces a step may point at — mirrors the schema enum. Unknown values
        # coming back from the model are dropped (the step stays, without a link).
        ENTRIES = %w[
          product_edit_ai
          translations_drawer
          product_media
          variant_inventory
          redirects
          publishing
        ].freeze

        # How many products of an issue are sampled into the prompt.
        SAMPLE_LIMIT = 5

        # Issues that can be decided for a single product. `redirect_unresolved`
        # is not one of them (a URL change is not a product row fact) — the
        # worklist still reports it.
        PRODUCT_ISSUE_KEYS = %w[
          missing_media
          missing_description
          missing_seo
          active_zero_stock
          old_drafts
          missing_translations
        ].freeze

        # What the issue means, in the prompt's language. Kept out of i18n on
        # purpose: the model reads English facts, the admin reads its own locale.
        ISSUE_DESCRIPTIONS = {
          'missing_media' => 'products without any image (product level and every variant)',
          'missing_description' => 'products without a description in the store default locale',
          'missing_seo' => 'products without a meta title or meta description in the store default locale',
          'missing_translations' => 'product translations missing in the store\'s other supported locales',
          'active_zero_stock' => 'active products with no stock on hand and no backorder/preorder',
          'redirect_unresolved' => 'product URL changes that never received a 301 redirect',
          'old_drafts' => 'draft products untouched for more than 30 days'
        }.freeze

        # @!attribute [r] status
        # @return [Symbol] :success, the gateway's failure status, or :rejected
        # @!attribute [r] summary
        #   @return [String, nil] one or two sentences of context
        # @!attribute [r] steps
        #   @return [Array<Hash>] `{ 'title' =>, 'detail' =>, 'entry' => }`
        # @!attribute [r] issue_key
        #   @return [String, nil] worklist granularity
        # @!attribute [r] issue_keys
        #   @return [Array<String>] product granularity
        # @!attribute [r] count
        #   @return [Integer, nil] worklist count (same number the page shows)
        # @!attribute [r] run_id
        #   @return [Integer, nil]
        # @!attribute [r] error_code
        #   @return [String, nil]
        Result = Struct.new(:status, :summary, :steps, :issue_key, :issue_keys, :count, :run_id, :error_code,
                            keyword_init: true) do
          def success?
            status.to_sym == :success
          end
        end

        # @param store [PallasTrade::Store]
        # @param actor [PallasTrade::AdminUser, nil]
        # @param issue_key [String] one of `PallasTrade::CatalogHealth::Issues::KEYS`
        # @return [Result]
        def self.generate(store:, actor:, issue_key:)
          new(store: store, actor: actor).generate(issue_key: issue_key)
        end

        # @param product [PallasTrade::Product]
        # @param actor [PallasTrade::AdminUser, nil]
        # @return [Result]
        def self.generate_for_product(product:, actor:)
          new(store: product.store, actor: actor).generate_for_product(product: product)
        end

        # Catalog health issues this product currently hits, in worklist order.
        # Reads the very same scopes the worklist counts.
        # @param product [PallasTrade::Product]
        # @return [Array<String>]
        def self.product_issue_keys(product, store: nil)
          store ||= product.store
          scope = PallasTrade::Product.where(id: product.id)

          keys = PallasTrade::CatalogHealth::Issues::PRODUCT_FILTER_KEYS.select do |key|
            PallasTrade::CatalogHealth::Issues.product_relation(scope, key, store: store)&.exists?
          end

          keys << 'missing_translations' if missing_translation_locales(product, store).any?
          keys
        end

        # Locales this product is still missing a `name` translation in — the same
        # rule the store-wide counter and the coverage page use.
        # @return [Array<String>]
        def self.missing_translation_locales(product, store)
          locales = other_locales(store)
          return [] if locales.empty?

          translated = product.translations.where(locale: locales).where.not(name: [nil, '']).pluck(:locale)
          locales - translated.map(&:to_s)
        end

        def self.other_locales(store)
          default = (store.default_locale.presence || I18n.default_locale).to_s
          store.supported_locales_list.map(&:to_s) - [default]
        end

        # @param store [PallasTrade::Store]
        # @param actor [PallasTrade::AdminUser, nil]
        def initialize(store:, actor:)
          @store = store
          @actor = actor
        end

        attr_reader :store, :actor

        # Worklist granularity.
        # @param issue_key [String]
        # @return [Result]
        def generate(issue_key:)
          key = issue_key.to_s

          return rejected(error_code: 'unknown_issue', issue_key: key) unless issue_valid?(key)

          count = PallasTrade::CatalogHealth::Report.call(store).count_for(key).to_i
          # Nothing to fix: answer without spending a model call or writing a Run.
          return rejected(error_code: 'nothing_to_fix', issue_key: key, count: count) if count.zero?

          result = gateway_call(input: catalog_input(key, count), resource: nil)

          build_result(result, issue_key: key, issue_keys: [key], count: count)
        end

        # Product granularity.
        # @param product [PallasTrade::Product]
        # @return [Result]
        def generate_for_product(product:)
          keys = self.class.product_issue_keys(product, store: store)

          return rejected(error_code: 'nothing_to_fix', issue_keys: []) if keys.empty?

          result = gateway_call(input: product_input(product, keys), resource: product)

          build_result(result, issue_keys: keys)
        end

        private

        def rejected(error_code:, issue_key: nil, issue_keys: [], count: nil)
          Result.new(status: :rejected, steps: [], issue_key: issue_key, issue_keys: issue_keys,
                     count: count, error_code: error_code)
        end

        def issue_valid?(key)
          PallasTrade::CatalogHealth::Issues.valid?(key)
        end

        def gateway_call(input:, resource:)
          PallasTrade::AI::Gateway.call(
            capability: CAPABILITY,
            store: store,
            actor: actor,
            input: input.merge(messages: [{ role: 'user', content: prompt(input) }],
                               system_instructions: system_instructions),
            resource: resource
          )
        end

        def build_result(result, issue_key: nil, issue_keys: [], count: nil)
          output = structured_output(result)

          Result.new(
            status: result.status,
            summary: (output['summary'] || output[:summary]).to_s.strip.presence,
            steps: normalize_steps(output['steps'] || output[:steps]),
            issue_key: issue_key,
            issue_keys: issue_keys,
            count: count,
            run_id: result.run&.id,
            error_code: result.error_code&.to_s
          )
        end

        def structured_output(result)
          return {} unless result.respond_to?(:output)

          output = result.output
          raw = output.respond_to?(:structured_output) ? output.structured_output : output
          raw.is_a?(Hash) ? raw : {}
        end

        # Keeps the step shape the admin can render; an `entry` outside the
        # whitelist is dropped (the step survives without a link) so a suggestion
        # can never advertise a surface that does not exist.
        def normalize_steps(raw)
          return [] unless raw.is_a?(Array)

          raw.filter_map do |step|
            next unless step.is_a?(Hash)

            title = (step['title'] || step[:title]).to_s.squish
            next if title.blank?

            entry = (step['entry'] || step[:entry]).to_s
            {
              'title' => title,
              'detail' => (step['detail'] || step[:detail]).to_s.squish.presence,
              'entry' => (ENTRIES.include?(entry) ? entry : nil)
            }
          end
        end

        def catalog_input(key, count)
          {
            scope: 'catalog',
            issue_key: key,
            issue_description: ISSUE_DESCRIPTIONS.fetch(key, key),
            count: count,
            store_locale: store_locale,
            sample: sample_for(key)
          }
        end

        def product_input(product, keys)
          {
            scope: 'product',
            product_name: product.name.to_s,
            product_status: product.status.to_s,
            issue_keys: keys,
            issue_descriptions: keys.map { |key| ISSUE_DESCRIPTIONS.fetch(key, key) },
            store_locale: store_locale,
            sample: [product_facts(product)]
          }
        end

        # Same scope the worklist counts, capped at SAMPLE_LIMIT products.
        def sample_for(key)
          return [] unless PallasTrade::CatalogHealth::Issues.valid_filter?(key)

          scope = PallasTrade::CatalogHealth::Issues.product_relation(store.products, key, store: store)
          return [] unless scope

          scope.limit(SAMPLE_LIMIT).map { |product| product_facts(product) }
        end

        # Deliberately minimal: catalog facts only — never customer, order, cost
        # or supplier data.
        def product_facts(product)
          {
            name: product.name.to_s,
            status: product.status.to_s,
            price: product.price.to_f.positive? ? 'present' : 'missing',
            stock_on_hand: product.total_on_hand.to_i
          }
        end

        def store_locale
          (store.default_locale.presence || I18n.default_locale).to_s
        end

        def system_instructions
          <<~PROMPT.squish
            You coach a merchant through fixing catalog health issues in a PallasTrade admin.
            Explain what the issue costs them and give an ordered plan that fixes the most valuable
            products first. Only recommend surfaces that exist in this admin, using these entry
            values: #{ENTRIES.join(', ')}. Never tell the merchant to let AI change prices, stock,
            channels or publishing state — every change is theirs to make and review. Answer with a
            JSON object holding "summary" (one or two sentences) and "steps" (3 to 6 objects with
            "title", optional "detail" and "entry").
          PROMPT
        end

        def prompt(input)
          facts = Array(input[:sample]).map do |fact|
            fact.map { |name, value| "#{name}: #{value}" }.join('; ')
          end

          <<~PROMPT.squish
            Catalog health data:
            #{facts.map { |line| "- #{line}" }.join("\n").presence || '(no product sample available)'}

            Issues to address:
            #{issue_lines(input)}

            Store default locale: #{store_locale}.
          PROMPT
        end

        def issue_lines(input)
          if input[:scope] == 'product'
            input[:issue_keys].map { |key| "- #{key}: #{ISSUE_DESCRIPTIONS.fetch(key, key)}" }.join("\n")
          else
            "- #{input[:issue_key]} (#{input[:count]} affected): #{input[:issue_description]}"
          end
        end
      end
    end
  end
end
