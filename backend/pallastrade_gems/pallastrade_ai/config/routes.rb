# frozen_string_literal: true

PallasTrade::Core::Engine.add_routes do
  namespace :api do
    namespace :v3 do
      namespace :admin do
        namespace :ai do
          # Settings
          get  'settings',  to: 'settings#show'
          patch 'settings', to: 'settings#update'

          # Provider types (read-only catalog)
          get 'provider_types', to: 'provider_types#index'

          # Providers
          resources :providers, only: %i[index create show update destroy] do
            member do
              post   :connection_tests, to: 'connection_tests#create'
              delete :credential, to: 'credentials#destroy'
            end
          end

          # Models
          resources :models, only: %i[index create show update destroy]

          # Capabilities
          get  'capabilities',           to: 'capabilities#index'
          get  'capability_settings',    to: 'capability_settings#index'
          patch 'capability_settings/:id', to: 'capability_settings#update'

          # Runs & Usage
          get 'runs',  to: 'runs#index'
          get 'runs/:id', to: 'runs#show'
          get 'usage', to: 'usage#index'
        end
      end
    end
  end
end
