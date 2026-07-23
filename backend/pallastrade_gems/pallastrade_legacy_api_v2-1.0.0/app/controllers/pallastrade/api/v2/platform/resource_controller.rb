module PallasTrade
  module Api
    module V2
      module Platform
        class ResourceController < ::PallasTrade::Api::V2::ResourceController
          # doorkeeper scopes usage: https://github.com/doorkeeper-gem/doorkeeper/wiki/Using-Scopes
          before_action :validate_token_client
          before_action -> { doorkeeper_authorize! :read, :admin }
          before_action -> { doorkeeper_authorize! :write, :admin }, if: :write_request?

          # optional authorization if using a user token instead of app token
          before_action :authorize_pallastrade_user

          # index and show actions are defined in PallasTrade::Api::V2::ResourceController

          def create
            resource = model_class.new(permitted_resource_params)
            ensure_current_store(resource)

            if resource.save
              render_serialized_payload(201) { serialize_resource(resource) }
            else
              render_error_payload(resource.errors)
            end
          end

          def update
            resource.assign_attributes(permitted_resource_params)
            ensure_current_store(resource)

            if resource.save
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload(resource.errors)
            end
          end

          def destroy
            if resource.destroy
              head 204
            else
              render_error_payload(resource.errors)
            end
          end

          protected

          def resource_serializer
            serializer_base_name = model_class.to_s.sub('PallasTrade::', '')
            "PallasTrade::Api::V2::Platform::#{serializer_base_name}Serializer".constantize
          end

          def collection_serializer
            resource_serializer
          end

          # overwriting to utilize ransack gem for filtering
          # https://github.com/activerecord-hackery/ransack#search-matchers
          def collection
            @collection ||= scope.ransack(params[:filter]).result
          end

          # overwriting to skip cancancan check if API is consumed by an application
          def scope
            return super if pallastrade_current_user.present?

            super(skip_cancancan: true)
          end

          # We're overwriting this method because the original one calls `dookreeper_authorize`
          # which breaks our application authorizations defined on top of this controller
          def pallastrade_current_user
            return nil unless doorkeeper_token
            return nil if doorkeeper_token.resource_owner_id.nil?
            return @pallastrade_current_user if @pallastrade_current_user

            @pallastrade_current_user ||= doorkeeper_token.resource_owner
          end

          def access_denied(exception)
            access_denied_401(exception)
          end

          def validate_token_client
            return if doorkeeper_token.nil?

            raise Doorkeeper::Errors::DoorkeeperError if doorkeeper_token.application.nil?
          end

          # if using a user oAuth token we need to check CanCanCan abilities
          # defined in https://github.com/stevenbian9266-cyber/pallastrade/blob/main/core/app/models/pallastrade/ability.rb
          def authorize_pallastrade_user
            return if pallastrade_current_user.nil?

            case action_name
            when 'create'
              pallastrade_authorize! :create, model_class
            when 'destroy'
              pallastrade_authorize! :destroy, resource
            when 'index'
              pallastrade_authorize! :read, model_class
            when 'show'
              pallastrade_authorize! :read, resource
            else
              pallastrade_authorize! :update, resource
            end
          end

          def model_param_name
            model_class.to_s.demodulize.underscore
          end

          def pallastrade_permitted_attributes
            store_ids = if model_class.method_defined?(:stores)
                          [{ store_ids: [] }]
                        else
                          []
                        end

            model_class.json_api_permitted_attributes + store_ids + metadata_params + metafields_params
          end

          def metadata_params
            if model_class.include?(Metadata)
              [{ public_metadata: {}, private_metadata: {} }]
            else
              []
            end
          end

          def metafields_params
            if PallasTrade::MetafieldDefinition.available_resources.map(&:name).include?(model_class.name) && model_class.method_defined?(:metafields)
              [{ metafields_attributes: PallasTrade::PermittedAttributes.metafield_attributes }]
            else
              []
            end
          end

          def permitted_resource_params
            params.require(model_param_name).permit(pallastrade_permitted_attributes)
          end

          def allowed_sort_attributes
            (super << pallastrade_permitted_attributes).uniq.compact
          end

          def write_request?
            %w[put patch post delete].include?(request.request_method.downcase)
          end
        end
      end
    end
  end
end
