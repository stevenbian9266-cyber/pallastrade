require 'rails/engine'

module PallasTrade
  module Dashboard
    class Engine < Rails::Engine
      isolate_namespace PallasTrade
      engine_name 'pallastrade_dashboard'
    end
  end
end
