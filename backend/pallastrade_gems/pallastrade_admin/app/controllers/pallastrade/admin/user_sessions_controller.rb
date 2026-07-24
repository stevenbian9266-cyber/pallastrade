module PallasTrade
  module Admin
    class UserSessionsController < defined?(Devise::SessionsController) ? Devise::SessionsController : PallasTrade::Admin::BaseController
      include PallasTrade::Admin::AuthRateLimiting
      include PallasTrade::Admin::LocaleConcern

      helper 'pallastrade/locale'
      helper 'pallastrade/admin/rtl'

      layout 'pallastrade/minimal'

      # This controller inherits from Devise::SessionsController, so the
      # `set_locale` before_action from PallasTrade::Core::ControllerHelpers::Locale
      # (mixed into PallasTrade::Admin::BaseController) never runs here — opt into
      # the concern's pre-auth locale handling instead (see LocaleConcern).
      before_action :set_login_locale

      auth_rate_limit :rate_limit_login, redirect_to: -> { new_session_path(resource_name) }

      # We need to overwrite this action because `return_to` url may be in a different domain
      # So we need to pass `allow_other_host` option to `redirect_to` method
      def create
        self.resource = warden.authenticate!(auth_options)
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        yield resource if block_given?

        destination = after_sign_in_path_for(resource)
        # A direct visit to the login form can be stored by Warden as the
        # return location. Redirecting an authenticated user back there makes
        # Devise's `require_no_authentication` loop forever on the same URL.
        destination = PallasTrade.admin_path if URI.parse(destination.to_s).path == new_session_path(resource_name)

        redirect_to destination, allow_other_host: true
      end

      protected

      def translation_scope
        'devise.user_sessions'
      end
    end
  end
end
