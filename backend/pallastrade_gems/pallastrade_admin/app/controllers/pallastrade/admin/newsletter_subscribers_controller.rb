module PallasTrade
  module Admin
    class NewsletterSubscribersController < ResourceController
      add_breadcrumb_icon 'users'
      add_breadcrumb PallasTrade.t(:customers), :admin_users_path
    end
  end
end
