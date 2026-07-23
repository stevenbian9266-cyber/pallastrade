module PallasTradeStripe
  class RegisterDomainJob < BaseJob
    def perform(model_id, klass_type = 'store')
      @klass_type = klass_type
      model = klass.find(model_id)
      RegisterDomain.new.call(model: model)
    end

    private

    def klass
      @klass ||= case @klass_type
                 when 'store'
                   PallasTrade::Store
                 when 'custom_domain'
                   PallasTrade::CustomDomain
                 end
    end
  end
end
