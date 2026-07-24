PallasTrade::Core::Engine.add_routes do
  namespace :admin, path: PallasTrade.admin_path do
    resources :properties, except: :show
  end
end
