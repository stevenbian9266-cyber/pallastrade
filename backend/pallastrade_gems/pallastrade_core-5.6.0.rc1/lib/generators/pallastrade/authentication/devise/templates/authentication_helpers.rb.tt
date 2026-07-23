module PallasTrade
  module AuthenticationHelpers
    def self.included(receiver)
      receiver.helper_method(
        :pallastrade_current_user,
        :pallastrade_login_path,
        :pallastrade_signup_path,
        :pallastrade_logout_path,
        :pallastrade_forgot_password_path,
        :pallastrade_edit_password_path,
        :pallastrade_admin_login_path,
        :pallastrade_admin_logout_path
      )
    end

    def pallastrade_current_user
      send("current_#{PallasTrade.user_class.model_name.singular_route_key}")
    end

    def pallastrade_login_path(opts = {})
      new_session_path(PallasTrade.user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_signup_path(opts = {})
      new_registration_path(PallasTrade.user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_logout_path(opts = {})
      destroy_session_path(PallasTrade.user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_forgot_password_path(opts = {})
      new_password_path(PallasTrade.user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_edit_password_path(opts = {})
      edit_registration_path(PallasTrade.user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_admin_login_path(opts = {})
      new_session_path(PallasTrade.admin_user_class.model_name.singular_route_key, opts)
    end

    def pallastrade_admin_logout_path(opts = {})
      destroy_session_path(PallasTrade.admin_user_class.model_name.singular_route_key, opts)
    end
  end
end

ApplicationController.include PallasTrade::AuthenticationHelpers if defined?(ApplicationController)
