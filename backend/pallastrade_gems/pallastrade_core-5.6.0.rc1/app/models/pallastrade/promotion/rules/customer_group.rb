module PallasTrade
  class Promotion
    module Rules
      class CustomerGroup < PromotionRule
        # Stored as raw IDs. Accepts prefixed IDs (`cg_…`) from API
        # callers and decodes them on write so eligibility checks can
        # compare against raw `customer_group_id` rows directly.
        preference :customer_group_ids, :array, default: [], parse_on_set: normalize_id_preference(klass: PallasTrade::CustomerGroup)

        def applicable?(promotable)
          promotable.is_a?(PallasTrade::Order)
        end

        def customer_groups
          return PallasTrade::CustomerGroup.none if preferred_customer_group_ids.blank?

          PallasTrade::CustomerGroup.where(id: preferred_customer_group_ids)
        end

        def eligible?(order, _options = {})
          return false unless order.user_id.present?
          return false if preferred_customer_group_ids.empty?

          user_customer_group_ids = PallasTrade::CustomerGroupUser.where(user_id: order.user_id).pluck(:customer_group_id).map(&:to_s)

          (preferred_customer_group_ids.map(&:to_s) & user_customer_group_ids).any?
        end
      end
    end
  end
end
