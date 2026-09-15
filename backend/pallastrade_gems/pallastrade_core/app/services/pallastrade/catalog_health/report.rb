# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # Builds the Catalog Health worklist for one store: every issue with its
    # count and where an admin goes to act on it
    # (PRD-20260915-admin-catalog-health-v1 FR-001/FR-002).
    #
    # The page is read-only: remediation happens in the products list (bulk
    # operations), the Product Translations coverage page or the Redirects page.
    class Report
      # @!attribute [r] key
      #   @return [String] issue key (`Issues::KEYS`)
      # @!attribute [r] count
      #   @return [Integer] how many things need attention
      # @!attribute [r] target
      #   @return [Symbol] `:products`, `:product_translations` or `:redirects`
      # @!attribute [r] params
      #   @return [Hash] query params for the products-list filters
      Issue = Struct.new(:key, :count, :target, :params, keyword_init: true)

      # Issues that link to a dedicated page instead of the filtered list.
      TARGETS = {
        'missing_translations' => :product_translations,
        'redirect_unresolved' => :redirects
      }.freeze

      def self.call(store)
        new(store).call
      end

      # @param store [PallasTrade::Store]
      def initialize(store)
        @store = store
      end

      attr_reader :store

      # @return [Array<Issue>] one entry per issue key, in display order
      def issues
        @issues ||= Issues::KEYS.map { |key| build_issue(key) }
      end

      # @return [Report] self, so callers can chain
      def call
        self
      end

      # @param key [String, Symbol]
      # @return [Integer]
      def count_for(key)
        issues.find { |issue| issue.key == key.to_s }&.count.to_i
      end

      # @return [Integer] sum of every issue (used by the page summary)
      def total
        issues.sum(&:count)
      end

      private

      def build_issue(key)
        Issue.new(
          key: key,
          count: safe_count(key),
          target: TARGETS.fetch(key, :products),
          params: Issues.valid_filter?(key) ? { health_issue: key } : {}
        )
      end

      def safe_count(key)
        Issues.count(store, key)
      rescue StandardError => e
        # One broken counter must not take the whole worklist down — the page
        # stays 200 and shows 0 for that issue (read-only ops page convention).
        Rails.logger.warn("[catalog_health] issue #{key} failed: #{e.class}: #{e.message}")
        0
      end
    end
  end
end
