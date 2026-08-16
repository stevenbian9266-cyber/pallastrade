module PallasTrade
  module Admin
    class ProfileController < BaseController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:profile), :admin_profile_path

      def edit
        @user = try_pallastrade_current_user
      end

      def update
        @user = try_pallastrade_current_user

        if @user.update(user_params)
          if params[:remove_avatar] == '1' && @user.avatar.attached?
            @user.avatar.detach
            @user.avatar.purge_later
          end

          flash[:success] = flash_message_for(@user, :successfully_updated)
          redirect_to PallasTrade.edit_admin_profile_path
        else
          render :edit, status: :unprocessable_content
        end
      end

      private

      def user_params
        params.require(:user).permit(permitted_user_attributes)
      end
    end
  end
end
