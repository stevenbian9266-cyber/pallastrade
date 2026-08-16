module PallasTrade
  module Admin
    # Unified breadcrumb for the Blog menu (Blog → posts list / editor),
    # mirroring EmailsBreadcrumbConcern / ProductsBreadcrumbConcern.
    module PostsBreadcrumbConcern
      extend ActiveSupport::Concern

      included do
        add_breadcrumb_icon 'news'
        add_breadcrumb PallasTrade.t(:blog), :admin_posts_path
      end
    end
  end
end
