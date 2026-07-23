module PallasTradeAdyen
  class AddAllowedOriginJob < PallasTradeAdyen::BaseJob
    def perform(record_id, gateway_id, klass_type = 'store')
      @klass_type = klass_type.to_s
      return unless klass

      record = klass.find(record_id)
      gateway = PallasTradeAdyen::Gateway.find(gateway_id)

      PallasTradeAdyen::Gateways::AddAllowedOrigin.new(record, gateway).call
    end

    private

    def klass
      @klass ||= case @klass_type
                 when 'store' then PallasTrade::Store
                 when 'custom_domain' then defined?(PallasTrade::CustomDomain) ? PallasTrade::CustomDomain : nil
                 else
                   Rails.error.unexpected("Unexpected klass_type: #{@klass_type}")
                 end
    end
  end
end
