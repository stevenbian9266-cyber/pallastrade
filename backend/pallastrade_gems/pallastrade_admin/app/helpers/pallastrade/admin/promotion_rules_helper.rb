module PallasTrade
  module Admin
    module PromotionRulesHelper
      # Class names still drive the picker links (`promotion_rule: { type: ... }`),
      # but the allowlist comes from the shared definition registry.
      def options_for_promotion_rule_types(promotion)
        existing = promotion.rules.pluck(:type)
        PallasTrade::Promotions::DefinitionRegistry.rule_classes.map(&:name).reject { |r| existing.include? r }
      end

      # Registry entries (key / label / description) for the promotion rule
      # picker. Labels come from the registry instead of reparsing class names,
      # so api_type renames (`taxon` → `category`, `user` → `customer`) resolve
      # to their real translation keys.
      def promotion_rule_entries(promotion)
        existing = promotion.rules.pluck(:type)
        PallasTrade::Promotions::DefinitionRegistry.rule_entries.reject do |entry|
          existing.include?(entry.type)
        end
      end

      # Admin form partial for a persisted rule. Resolved through the registry so
      # the api_type → partial mapping has a single source (unknown types fall back
      # to the legacy convention instead of raising).
      def promotion_rule_form_partial(promotion_rule)
        PallasTrade::Promotions::DefinitionRegistry.admin_partial_for(
          promotion_rule.type, kind: PallasTrade::Promotions::DefinitionRegistry::RULE
        ) || "pallastrade/admin/promotion_rules/forms/#{promotion_rule.key}"
      end

      def active_options_for_option_value_promotion_rule(promotion_rule)
        eligible_values = promotion_rule.preferred_eligible_values || []
        return [] if eligible_values.empty?

        PallasTrade::OptionValue.includes(:option_type).where(id: eligible_values).map do |ov|
          {
            id: ov.id,
            name: ov.display_presentation
          }
        end
      end

      # Returns the promotion rule option values
      # @param value_ids [Array<Integer>]
      # @return [Array<String>]
      def promotion_rule_option_values(value_ids)
        PallasTrade::OptionValue.includes(:option_type).where(id: value_ids).map(&:display_presentation)
      end
    end
  end
end
