# frozen_string_literal: true

module PallasTrade
  module Promotions
    # Read-only projection that answers, in one object, what promotion rules and
    # actions this application knows about and what each one is capable of:
    #
    #   * `key` / `api_type`       — wire shorthand (`category`, `customer`, …)
    #   * `type`                   — the STI class name persisted in the DB
    #   * `calculators`            — calculators the action accepts
    #   * `allowed_attributes`     — extra permitted params merged by the Admin API
    #   * `admin_partial`          — the Rails Admin form partial that renders it
    #   * `locale_key`             — where the label / description come from
    #
    # The registration arrays stay authoritative and untouched — extensions keep
    # appending to `PallasTrade.promotions.rules` / `PallasTrade.promotions.actions`
    # (and to the calculator buckets) and this registry reflects them. It exists to
    # remove the "four places to register, no way to notice a miss" drift between
    # the engine registrations, the calculator buckets, the admin form partials and
    # the locale files.
    #
    # PRD-20260910-promotions-promo-batch5a-definition-registry (PR-P7-1..3)
    class DefinitionRegistry
      RULE = :rule
      ACTION = :action
      KINDS = [RULE, ACTION].freeze

      RULE_PARENT = 'PallasTrade::PromotionRule'
      ACTION_PARENT = 'PallasTrade::PromotionAction'

      ADMIN_PARTIAL_NAMESPACES = {
        RULE => 'pallastrade/admin/promotion_rules/forms',
        ACTION => 'pallastrade/admin/promotion_actions/forms'
      }.freeze

      LOCALE_NAMESPACES = {
        RULE => 'promotion_rule_types',
        ACTION => 'promotion_action_types'
      }.freeze

      # `level` is one of :error / :warning.
      #   error   — the registry is inconsistent; some surface will break at runtime
      #   warning — degraded but functional (locale falls back to a titleized key,
      #             an unregistered subclass stays invisible to the admin picker)
      VALIDATION_CODES = {
        duplicate_api_type: :error,
        invalid_sti_parent: :error,
        missing_admin_partial: :error,
        missing_calculator: :error,
        invalid_allowed_attributes: :error,
        missing_locale: :warning,
        unregistered_class: :warning
      }.freeze

      # One registered rule/action, projected for every consumer that needs to
      # describe it (admin pickers, `/types` endpoints, validation, docs).
      Entry = Struct.new(:key, :type, :kind, :klass, :label, :description, :calculators,
                         :allowed_attributes, :admin_partial, :locale_key, :calculator_required,
                         keyword_init: true) do
        def rule?
          kind == RULE
        end

        def action?
          kind == ACTION
        end

        def calculator_required?
          calculator_required
        end

        def calculator_types
          calculators.map(&:to_s)
        end

        def to_h
          {
            key: key,
            type: type,
            kind: kind,
            label: label,
            description: description,
            calculators: calculator_types,
            allowed_attributes: allowed_attributes,
            admin_partial: admin_partial,
            locale_key: locale_key,
            calculator_required: calculator_required?
          }
        end
      end

      class << self
        # Registry view scoped to a single kind — the shape API/Admin controllers
        # consume (`DefinitionRegistry.for(:rule).classes`).
        def for(kind)
          Kind.new(normalize_kind(kind))
        end

        # @return [Array<Class>] registered rule classes (the engine array itself)
        def rule_classes
          Array(PallasTrade.promotions.rules)
        end

        # @return [Array<Class>] registered action classes (the engine array itself)
        def action_classes
          Array(PallasTrade.promotions.actions)
        end

        def classes_for(kind)
          normalize_kind(kind) == RULE ? rule_classes : action_classes
        end

        # @param kind [Symbol, String, nil] :rule / :action / nil (all entries)
        # @param classes [Array<Class>, nil] override the registered classes
        #   (used by `validate!` specs to describe synthetic gaps without
        #   mutating `PallasTrade.promotions.*`)
        # @return [Array<Entry>]
        def entries(kind = nil, classes: nil)
          kinds = kind.nil? ? KINDS : [normalize_kind(kind)]
          kinds.flat_map { |k| build_entries(k, classes) }
        end

        def rule_entries
          entries(RULE)
        end

        def action_entries
          entries(ACTION)
        end

        def keys(kind = nil)
          entries(kind).map(&:key)
        end

        def types(kind = nil)
          entries(kind).map(&:type)
        end

        # Resolves a shorthand (`'category'`), a full class name, or a class itself
        # to a registry entry. Returns nil for unknown/foreign input.
        #
        # @return [Entry, nil]
        def entry_for(value, kind: nil)
          return nil if value.nil?

          candidate = value.to_s
          entries(kind).find do |entry|
            entry.type == candidate || entry.key == candidate
          end
        end

        # @return [Class, nil]
        def find_by_api_type(value, kind: nil)
          entry_for(value, kind: kind)&.klass
        end

        # @return [String, nil] the wire shorthand for a shorthand / class name / class
        def api_type_for(value, kind: nil)
          entry_for(value, kind: kind)&.key
        end

        # @return [Symbol, nil] :rule or :action when the value is registered
        def kind_for(value)
          entry_for(value)&.kind
        end

        # @return [Array<Class>] calculators the action accepts ([] for rules)
        def calculators_for(value, kind: nil)
          entry_for(value, kind: kind)&.calculators || []
        end

        # @return [Array] extra permitted params merged by the Admin API
        def allowed_attributes_for(value, kind: nil)
          entry_for(value, kind: kind)&.allowed_attributes || []
        end

        # @return [String, nil] view path (without leading slash) of the admin form partial
        def admin_partial_for(value, kind: nil)
          entry_for(value, kind: kind)&.admin_partial
        end

        # @return [Array<Hash>] `[{ level:, code:, key:, message: }]`, errors first
        def validate!(kinds: KINDS, classes: nil)
          raise ArgumentError, 'classes: requires a single kind' if classes && Array(kinds).size != 1

          Array(kinds).flat_map { |kind| Validator.new(kind: normalize_kind(kind), classes: classes).issues }.
            sort_by { |issue| issue[:level] == :error ? 0 : 1 }
        end

        def valid?(kinds: KINDS, classes: nil)
          validate!(kinds: kinds, classes: classes).none? { |issue| issue[:level] == :error }
        end

        # True when the admin form partial for the entry exists in the host app or
        # in any engine's view paths.
        def admin_partial_available?(entry)
          lookup_context.exists?(entry.admin_partial, [], true)
        rescue StandardError
          # View paths can be unavailable outside a booted application (e.g. pure
          # unit contexts). Treat "cannot tell" as available so validation never
          # produces false errors; the spec asserts the real lookup path.
          true
        end

        def locale_available?(entry)
          !PallasTrade.t("#{entry.locale_key}.name", default: nil).nil?
        rescue StandardError
          true
        end

        private

        def normalize_kind(kind)
          normalized = kind.to_s.downcase.to_sym
          raise ArgumentError, "Unknown promotion definition kind: #{kind.inspect}" unless KINDS.include?(normalized)

          normalized
        end

        def build_entries(kind, classes = nil)
          Array(classes || classes_for(kind)).filter_map do |klass|
            next nil unless klass.respond_to?(:api_type)

            build_entry(kind, klass)
          end
        end

        def build_entry(kind, klass)
          key = klass.api_type
          Entry.new(
            key: key,
            type: klass.to_s,
            kind: kind,
            klass: klass,
            label: klass.respond_to?(:human_name) ? klass.human_name : key.titleize,
            description: klass.respond_to?(:human_description) ? klass.human_description : nil,
            calculators: klass.respond_to?(:calculators) ? Array(klass.calculators) : [],
            allowed_attributes: allowed_attributes_of(klass),
            admin_partial: "#{ADMIN_PARTIAL_NAMESPACES[kind]}/#{key}",
            locale_key: "#{LOCALE_NAMESPACES[kind]}.#{key}",
            calculator_required: klass.respond_to?(:calculators)
          )
        end

        def allowed_attributes_of(klass)
          klass.respond_to?(:additional_permitted_attributes) ? klass.additional_permitted_attributes : []
        end

        def lookup_context
          @lookup_context ||= ActionView::LookupContext.new(ActionController::Base.view_paths)
        end
      end

      # Kind-scoped facade (`DefinitionRegistry.for(:rule)`).
      class Kind
        attr_reader :kind

        def initialize(kind)
          @kind = kind
        end

        def classes
          DefinitionRegistry.classes_for(kind)
        end

        def entries
          DefinitionRegistry.entries(kind)
        end

        def keys
          entries.map(&:key)
        end

        def types
          entries.map(&:type)
        end

        def entry_for(value)
          DefinitionRegistry.entry_for(value, kind: kind)
        end

        def find_by_api_type(value)
          DefinitionRegistry.find_by_api_type(value, kind: kind)
        end

        def api_type_for(value)
          DefinitionRegistry.api_type_for(value, kind: kind)
        end

        def calculators_for(value)
          DefinitionRegistry.calculators_for(value, kind: kind)
        end

        def allowed_attributes_for(value)
          DefinitionRegistry.allowed_attributes_for(value, kind: kind)
        end

        def admin_partial_for(value)
          DefinitionRegistry.admin_partial_for(value, kind: kind)
        end

        def validate!
          DefinitionRegistry.validate!(kinds: [kind])
        end
      end

      # Consistency checks behind `validate!` / `pallastrade:promotions:definitions:validate`.
      class Validator
        attr_reader :kind

        def initialize(kind:, classes: nil)
          @kind = kind
          @classes = classes
        end

        def issues
          [
            *duplicate_api_type_issues,
            *parent_issues,
            *calculator_issues,
            *allowed_attributes_issues,
            *admin_partial_issues,
            *locale_issues,
            *unregistered_class_issues
          ]
        end

        private

        def entries
          @entries ||= DefinitionRegistry.entries(kind, classes: @classes)
        end

        def parent_class
          @parent_class ||= (kind == RULE ? RULE_PARENT : ACTION_PARENT).constantize
        end

        def issue(code, key, message)
          { level: VALIDATION_CODES.fetch(code), code: code, key: key, kind: kind, message: message }
        end

        def duplicate_api_type_issues
          entries.group_by(&:key).filter_map do |key, grouped|
            next if grouped.size < 2

            issue(:duplicate_api_type, key,
                  "#{grouped.size} #{kind} classes share api_type '#{key}': #{grouped.map(&:type).join(', ')}")
          end
        end

        def parent_issues
          entries.filter_map do |entry|
            next if entry.klass <= parent_class

            issue(:invalid_sti_parent, entry.key,
                  "#{entry.type} does not inherit from #{parent_class.name}")
          end
        end

        def calculator_issues
          entries.filter_map do |entry|
            next unless entry.calculator_required? && entry.calculators.empty?

            issue(:missing_calculator, entry.key,
                  "#{entry.type} accepts calculators but none are registered in PallasTrade.calculators " \
                  "(see the engine's promotion_actions_create_* buckets)")
          end
        end

        def allowed_attributes_issues
          entries.filter_map do |entry|
            next if entry.allowed_attributes.is_a?(Array)

            issue(:invalid_allowed_attributes, entry.key,
                  "#{entry.type}.additional_permitted_attributes must return an Array, got " \
                  "#{entry.allowed_attributes.class}")
          end
        end

        def admin_partial_issues
          entries.filter_map do |entry|
            next if DefinitionRegistry.admin_partial_available?(entry)

            issue(:missing_admin_partial, entry.key,
                  "missing admin form partial #{entry.admin_partial}")
          end
        end

        def locale_issues
          entries.filter_map do |entry|
            next if DefinitionRegistry.locale_available?(entry)

            issue(:missing_locale, entry.key,
                  "missing locale key #{entry.locale_key}.name " \
                  "(the admin picker falls back to a titleized key)")
          end
        end

        def unregistered_class_issues
          registered = entries.to_set { |entry| entry.klass.to_s }
          descendants = parent_class.descendants.select do |klass|
            klass.name.present? && klass.name != parent_class.name
          end

          issues = descendants.filter_map do |klass|
            next if registered.include?(klass.to_s)
            next unless klass.respond_to?(:api_type)

            issue(:unregistered_class, klass.api_type,
                  "#{klass} is a #{parent_class.name} subclass but is not registered in " \
                  "PallasTrade.promotions.#{kind == RULE ? 'rules' : 'actions'}")
          end

          issues.sort_by { |entry| entry[:key] }
        rescue StandardError
          []
        end
      end
    end
  end
end
