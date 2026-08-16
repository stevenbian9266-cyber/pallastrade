# frozen_string_literal: true

module PallasTrade
  module Admin
    class ApiKeysController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern
      # 面包屑由导航配置自动推导（P5）：Settings > API Keys

      helper 'pallastrade/admin/api_keys'

      def create
        invoke_callbacks(:create, :before)
        set_created_by
        @object.attributes = permitted_resource_params
        if @object.save
          invoke_callbacks(:create, :after)
          if @object.secret?
            # Pass plaintext token via flash so the show page can display it once.
            # Flash is stored in the encrypted session cookie and auto-cleared after one request.
            # Skip the success flash — the token warning banner is sufficient feedback.
            flash[:plaintext_token] = @object.plaintext_token
          else
            flash[:success] = message_after_create
          end
          redirect_to location_after_create, status: :see_other
        else
          invoke_callbacks(:create, :fails)
          render action: :new, status: :unprocessable_content
        end
      end

      def revoke
        @object = scope.find_by_prefix_id!(params[:id])
        @object.revoke!(try_pallastrade_current_user)
        flash[:success] = PallasTrade.t('admin.api_keys.revoked')
        redirect_to PallasTrade.admin_api_key_path(@object)
      end

      private

      def model_class
        PallasTrade::ApiKey
      end

      def scope
        current_store.api_keys
      end

      def object_name
        'api_key'
      end

      def permitted_resource_params
        # `key_type` and `scopes` are create-only (scope immutability lives on
        # PallasTrade::ApiKey); only the human-facing `name` is editable afterward.
        return params.require(:api_key).permit(:name) unless action_name == 'create'

        params.require(:api_key).permit(permitted_api_key_attributes)
      end

      def location_after_save
        PallasTrade.admin_api_key_path(@object)
      end

      def update_turbo_stream_enabled?
        true
      end

      def build_resource
        if params[:api_key].present?
          scope.new(permitted_resource_params.merge(created_by: try_pallastrade_current_user))
        else
          scope.new(created_by: try_pallastrade_current_user)
        end
      end
    end
  end
end
