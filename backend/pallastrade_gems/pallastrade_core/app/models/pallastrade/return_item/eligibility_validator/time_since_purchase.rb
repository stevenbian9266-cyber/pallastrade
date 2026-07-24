module PallasTrade
  class ReturnItem::EligibilityValidator::TimeSincePurchase < PallasTrade::ReturnItem::EligibilityValidator::BaseValidator
    def eligible_for_return?
      if (@return_item.inventory_unit.order.completed_at + PallasTrade::Config[:return_eligibility_number_of_days].days) > Time.current
        true
      else
        add_error(:number_of_days, PallasTrade.t('return_item_time_period_ineligible'))
        false
      end
    end

    def requires_manual_intervention?
      false
    end
  end
end
