module PallasTrade
  module Core
    module ControllerHelpers
      module Auth
        extend ActiveSupport::Concern

        included do
          if defined?(helper_method)
            helper_method :try_pallastrade_current_user
          end

          rescue_from CanCan::AccessDenied do |_exception|
            redirect_unauthorized_access
          end
        end

        # Needs to be overridden so that we use Spree's Ability rather than anyone else's.
        def current_ability
          @current_ability ||= PallasTrade.ability_class.new(try_pallastrade_current_user, { store: current_store })
        end

        # this will work for devise out of the box
        # for other auth systems you will need to override this method
        def store_location(location = nil)
          return if try_pallastrade_current_user

          location ||= request.fullpath
          session_key = store_location_session_key

          session[session_key] = location
        end

        def store_location_session_key
          "#{PallasTrade.user_class.model_name.singular_route_key.to_sym}_return_to"
        end

        # proxy method to *possible* pallastrade_current_user method
        # Authentication extensions (such as PALLASTRADE_auth_devise) are meant to provide pallastrade_current_user
        def try_pallastrade_current_user
          # This one will be defined by apps looking to hook into Spree
          # As per authentication_helpers.rb
          if respond_to?(:pallastrade_current_user)
            pallastrade_current_user
          # This one will be defined by Devise
          elsif respond_to?(:current_PALLASTRADE_user)
            current_PALLASTRADE_user
          end
        end
      end
    end
  end
end
