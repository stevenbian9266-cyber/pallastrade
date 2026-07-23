module PallasTrade
  module Api
    module V3
      module Admin
        # CRUD for `PallasTrade::PromotionRule` STI subclasses. Same shape as
        # PromotionActionsController — only the registry differs
        # (`PallasTrade.promotions.rules` instead of `PallasTrade.promotions.actions`).
        class PromotionRulesController < ResourceController
          include PallasTrade::Api::V3::Admin::SubclassedResource

          scoped_resource :promotions

          subclassed_via -> { PallasTrade.promotions.rules },
                         unknown_type_error: 'unknown_promotion_rule_type'

          def types
            authorize! :read, model_class

            render json: { data: model_class.subclasses_with_preference_schema }
          end

          protected

          def model_class
            PallasTrade::PromotionRule
          end

          def serializer_class
            PallasTrade.api.admin_promotion_rule_serializer
          end

          def permitted_params
            params.permit(:type, preferences: {})
          end

          def set_parent
            return if action_name == 'types'

            @parent = current_store.promotions.accessible_by(current_ability, :update)
                                   .find_by_prefix_id!(params[:promotion_id])
          end

          def parent_association
            :promotion_rules
          end

          private

          def build_subclassed_resource(klass, attrs)
            klass.new(attrs.merge(promotion: @parent))
          end
        end
      end
    end
  end
end
