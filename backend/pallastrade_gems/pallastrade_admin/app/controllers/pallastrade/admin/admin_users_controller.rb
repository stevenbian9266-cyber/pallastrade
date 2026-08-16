module PallasTrade
  module Admin
    class AdminUsersController < BaseController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Users；show 追加用户 email

      skip_before_action :authorize_admin, only: [:new, :create]
      before_action :load_parent, except: [:new, :create, :select_options]
      before_action :load_roles, except: [:index, :select_options]
      before_action :load_invitation, only: [:new, :create]
      before_action :load_admin_user, only: [:show, :edit, :update, :destroy]

      helper_method :object_url

      # GET /admin/admin_users
      def index
        @search = scope.includes(role_users: :role, avatar_attachment: :blob).
                  where(role_users: { resource: @parent }).
                  ransack(params[:q])
        @collection = @search.result
      end

      # GET /admin/admin_users/select_options.json
      def select_options
        q = params[:q]
        ransack_params = q.is_a?(String) ? { email_cont: q } : q
        users = PallasTrade.admin_user_class.accessible_by(current_ability).ransack(ransack_params).result.order(:email).limit(50)

        render json: users.pluck(:id, :email).map { |id, email| { id: id, name: email } }
      end

      # GET /admin/admin_users/:id
      def show
        authorize! :read, @admin_user
        @role_users = @admin_user.role_users.includes(:role).where(resource: @parent)

        add_breadcrumb @admin_user.email, PallasTrade.admin_admin_user_path(@admin_user)
      end

      # GET /admin/admin_users/new?token=<token>
      # this is a self signup flow for admin users from the invitation email
      def new
        @admin_user = PallasTrade.admin_user_class.new
        @admin_user.email = @invitation.email
      end

      # POST /admin/admin_users
      # this is a self signup flow for admin users from the invitation email
      def create
        @admin_user = PallasTrade.admin_user_class.new(permitted_params)
        @invitation.invitee = @admin_user
        if @admin_user.save && @invitation.accept!
          # Automatically log in the user after successful signup
          # if Devise is installed
          if defined?(sign_in)
            sign_in(PallasTrade.admin_user_class.model_name.singular_route_key, @admin_user)
          end
          redirect_to PallasTrade.admin_path
        else
          render :new, status: :unprocessable_content
        end
      end

      # GET /admin/admin_users/:id/edit
      def edit
        authorize! :update, @admin_user
      end

      # PUT /admin/admin_users/:id
      def update
        authorize! :update, @admin_user

        permitted_params = params.require(:admin_user).permit(permitted_user_attributes | [pallastrade_role_ids: []])

        if @admin_user.update(permitted_params)
          redirect_to PallasTrade.admin_admin_user_path(@admin_user), status: :see_other, notice: flash_message_for(@admin_user, :successfully_updated)
        else
          render :edit, status: :unprocessable_content
        end
      end

      # DELETE /admin/admin_users/:id
      def destroy
        authorize! :destroy, @admin_user
        if @admin_user.destroy
          redirect_to PallasTrade.admin_admin_users_path, status: :see_other, notice: flash_message_for(@admin_user, :successfully_removed)
        else
          flash[:error] = @admin_user.errors.full_messages.to_sentence
          redirect_to PallasTrade.admin_admin_users_path, status: :see_other
        end
      end

      private

      def permitted_params
        params.require(:admin_user).permit(:email, :password, :password_confirmation, :first_name, :last_name)
      end

      def load_invitation
        raise ActiveRecord::RecordNotFound if params[:token].blank?

        @invitation = PallasTrade::Invitation.pending.not_expired.find_by!(token: params[:token])
      end

      def load_parent
        @parent = current_store
      end

      def scope
        @parent.users.accessible_by(current_ability, :manage)
      end

      def load_admin_user
        @admin_user = PallasTrade.admin_user_class.accessible_by(current_ability).find_by_prefix_id!(params[:id])
      end

      # for self signup flow, we use the minimal layout
      def choose_layout
        # P4 单一布局：设置区复用主布局；仅邀请自助注册用 minimal
        @invitation.present? ? 'pallastrade/minimal' : 'pallastrade/admin'
      end

      def load_roles
        @roles = PallasTrade::Role.accessible_by(current_ability)
      end

      def model_class
        PallasTrade.admin_user_class
      end

      def object_url
        PallasTrade.admin_admin_user_path(@admin_user)
      end
    end
  end
end
