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
