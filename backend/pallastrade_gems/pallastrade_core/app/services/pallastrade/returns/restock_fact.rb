# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-5 (PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept)
#
# Returns::RestockFact —— Restock Fact Resolver（源文档 REV-P6 §41）：
#   输出 NOT_REQUIRED / PENDING / RESTOCKED / NOT_RESTOCKABLE / AMBIGUOUS。
#   证据来自 ReturnItem / InventoryUnit / StockMovement（return_item_id 幂等键），
#   不是 Refund state；只读派生、不持久化、不猜（存量无事实 → 归 PENDING 由其上游收敛，
#   REV-P6-3「不可证明不猜」原则）。REV-P6-6 ReverseCommerce::Recover 消费本事实。
module PallasTrade
  module Returns
    class RestockFact
      RESTOCKED = :restocked
      NOT_REQUIRED = :not_required
      NOT_RESTOCKABLE = :not_restockable
      PENDING = :pending
      AMBIGUOUS = :ambiguous

      # @param return_item [PallasTrade::ReturnItem]
      # @return [Symbol] RESTOCKED / NOT_REQUIRED / NOT_RESTOCKABLE / PENDING / AMBIGUOUS
      def self.resolve(return_item:)
        return PENDING unless return_item

        if return_item.accepted?
          if return_item.restock_eligible?
            movement_exists = PallasTrade::StockMovement.where(return_item_id: return_item.id).exists?
            movement_exists ? RESTOCKED : AMBIGUOUS
          else
            NOT_RESTOCKABLE
          end
        elsif return_item.manual_intervention_required? || return_item.pending?
          PENDING # 未决（含 receive 后待人工裁决）——未到 Restock Decision
        elsif return_item.reception_completed? # rejected / given_to_customer
          NOT_REQUIRED
        elsif return_item.cancelled?
          NOT_REQUIRED
        else # pending / manual_intervention_required
          PENDING
        end
      end

      # @param customer_return [PallasTrade::CustomerReturn]
      # @return [Hash{Integer => Symbol}] return_item_id => fact
      def self.resolve_for_customer_return(customer_return:)
        customer_return.return_items.each_with_object({}) do |item, acc|
          acc[item.id] = resolve(return_item: item)
        end
      end
    end
  end
end
