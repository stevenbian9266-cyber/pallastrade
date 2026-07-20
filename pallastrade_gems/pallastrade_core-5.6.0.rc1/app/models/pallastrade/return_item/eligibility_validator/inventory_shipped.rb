module PallasTrade
  class ReturnItem::EligibilityValidator::InventoryShipped < PallasTrade::ReturnItem::EligibilityValidator::BaseValidator
    def eligible_for_return?
      if @return_item.inventory_unit.shipped?
        true
      else
        add_error(:inventory_unit_shipped, PallasTrade.t('return_item_inventory_unit_ineligible'))
        false
      end
    end

    def requires_manual_intervention?
      @errors.present?
    end
  end
end
