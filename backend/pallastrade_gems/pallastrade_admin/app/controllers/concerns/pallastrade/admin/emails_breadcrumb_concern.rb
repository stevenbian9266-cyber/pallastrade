module PallasTrade
  module Admin
    # Unified breadcrumb for the Email menu (Email → Settings / Scenarios /
    # Templates / Outbox / Inbox), mirroring ProductsBreadcrumbConcern /
    # OrderBreadcrumbConcern. Every Email sub-page includes this concern and
    # then adds its own sub-page crumb.
    module EmailsBreadcrumbConcern
      extend ActiveSupport::Concern

      included do
        add_breadcrumb_icon 'send'
        add_breadcrumb PallasTrade.t(:emails), :admin_emails_path
      end
    end
  end
end
