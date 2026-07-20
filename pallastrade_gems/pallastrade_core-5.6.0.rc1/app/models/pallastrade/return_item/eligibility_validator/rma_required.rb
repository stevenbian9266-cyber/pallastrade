module PallasTrade
  class ReturnItem::EligibilityValidator::RMARequired < PallasTrade::ReturnItem::EligibilityValidator::BaseValidator
    def eligible_for_return?
      if @return_item.return_authorization.present?
        true
      else
        add_error(:rma_required, PallasTrade.t('return_item_rma_ineligible'))
        false
      end
    end

    def requires_manual_intervention?
      false
    end
  end
end
