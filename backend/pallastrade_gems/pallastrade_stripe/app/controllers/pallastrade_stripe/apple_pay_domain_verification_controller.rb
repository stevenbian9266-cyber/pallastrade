module PallasTradeStripe
  class ApplePayDomainVerificationController < PallasTrade::BaseController
    def show
      gateway = PallasTradeStripe::Gateway.last

      raise ActiveRecord::RecordNotFound if gateway.nil? || !gateway.apple_domain_association_file_content

      render plain: gateway.apple_domain_association_file_content
    end
  end
end
