module PallasTrade
  module Admin
    module PromotionActionsHelper
      def options_for_promotion_action_types(promotion)
        existing = promotion.actions.pluck(:type)
        PallasTrade::Promotions::DefinitionRegistry.action_classes.map(&:name).reject { |r| existing.include? r }
      end

      # See `PromotionRulesHelper#promotion_action_form_partial`.
      def promotion_action_entries(promotion)
        existing = promotion.actions.pluck(:type)
        PallasTrade::Promotions::DefinitionRegistry.action_entries.reject do |entry|
          existing.include?(entry.type)
        end
      end

      def promotion_action_form_partial(promotion_action)
        PallasTrade::Promotions::DefinitionRegistry.admin_partial_for(
          promotion_action.type, kind: PallasTrade::Promotions::DefinitionRegistry::ACTION
        ) || "pallastrade/admin/promotion_actions/forms/#{promotion_action.key}"
      end
    end
  end
end
