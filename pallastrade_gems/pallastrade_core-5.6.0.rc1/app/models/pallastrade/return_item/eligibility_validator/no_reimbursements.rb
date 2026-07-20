module PallasTrade
  class ReturnItem::EligibilityValidator::NoReimbursements < PallasTrade::ReturnItem::EligibilityValidator::BaseValidator
    def eligible_for_return?
      if PallasTrade::ReturnItem.where(inventory_unit: @return_item.inventory_unit).where.not(reimbursement_id: nil).any?
        add_error(:inventory_unit_reimbursed, PallasTrade.t('return_item_inventory_unit_reimbursed'))
        false
      else
        true
      end
    end

    def requires_manual_intervention?
      @errors.present?
    end
  end
end
