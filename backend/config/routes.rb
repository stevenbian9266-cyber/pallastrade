require 'sidekiq/web'

Rails.application.routes.draw do
  PallasTrade::Core::Engine.add_routes do
    # Admin authentication
    devise_for(
      PallasTrade.admin_user_class.model_name.singular_route_key,
      class_name: PallasTrade.admin_user_class.to_s,
      controllers: {
        sessions: 'pallastrade/admin/user_sessions',
        passwords: 'pallastrade/admin/user_passwords'
      },
      skip: :registrations,
      path: :admin_user,
      router_name: :pallastrade
    )

    # AI Tools admin pages
    scope path: PallasTrade.admin_path, module: 'admin' do
      get 'ai', to: 'ai#index', as: :admin_ai
      get 'ai/providers', to: 'ai#providers', as: :admin_ai_providers
      get 'ai/providers/:id', to: 'ai#provider', as: :admin_ai_provider
      patch 'ai/providers/:id', to: 'ai#update_provider', as: :admin_ai_update_provider
      post 'ai/providers/:id/test_connection', to: 'ai#test_connection', as: :admin_ai_test_connection
      delete 'ai/providers/:id/credential', to: 'ai#clear_credential', as: :admin_ai_clear_credential
      get 'ai/models', to: 'ai#models', as: :admin_ai_models
      patch 'ai/models/:id', to: 'ai#update_model', as: :admin_ai_update_model
      get 'ai/capabilities', to: 'ai#capabilities', as: :admin_ai_capabilities
      patch 'ai/capabilities/:capability_key', to: 'ai#update_capability', as: :admin_ai_update_capability
      get 'ai/runs', to: 'ai#runs', as: :admin_ai_runs
      patch 'ai/settings', to: 'ai#update_settings', as: :admin_ai_update_settings
    end
  end
  # This line mounts PallasTrade's routes at the root of your application.
  # This means, any requests to URLs such as /products, will go to
  # PallasTrade::ProductsController.
  # If you would like to change where this engine is mounted, simply change the
  # :at option to something different.
  #
  # We ask that you don't use the :as option here, as PallasTrade relies on it being
  # the default of "pallastrade".
  mount PallasTrade::Core::Engine, at: '/'
  devise_for :admin_users, class_name: "PallasTrade::AdminUser"
  devise_for :users, class_name: "PallasTrade::User"

  # Sidekiq Web UI — accessible to any authenticated admin user
  authenticate :admin_user do
    mount Sidekiq::Web => "/sidekiq"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root to: redirect('/admin')
end
