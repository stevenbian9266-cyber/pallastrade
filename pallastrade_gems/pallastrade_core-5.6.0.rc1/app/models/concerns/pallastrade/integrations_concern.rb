module PallasTrade
  module IntegrationsConcern
    def store_integrations
      @store_integrations ||= PallasTrade::Store.current.integrations.active.to_a
    end

    def store_integration(name)
      store_integrations.find { |integration| integration.type.to_s.demodulize.underscore == name }
    end
  end
end
