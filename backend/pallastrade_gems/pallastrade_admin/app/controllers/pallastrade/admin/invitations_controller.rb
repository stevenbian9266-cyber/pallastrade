module PallasTrade
  module Admin
    class InvitationsController < BaseController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:invitations), :admin_invitations_path

      skip_before_action :authorize_admin, only: [:show, :accept]

      before_action :load_parent, except: [:show]
      before_action :load_invitation, only: [:destroy]
      before_action :load_roles, only: [:new, :create]

      layout :choose_layout

      # GET /admin/invitations
      def index
        @search = scope.includes(:inviter, :role).ransack(params[:q])
        @collection = @search.result
      end

      # GET /admin/invitations/new
      def new
        authorize! :create, PallasTrade::Invitation
        authorize! :manage, @parent

        @invitation = PallasTrade::Invitation.new
        @invitation.resource = @parent
        @invitation.inviter = try_pallastrade_current_user
      end

      # POST /admin/invitations
      def create
        authorize! :create, PallasTrade::Invitation
        authorize! :manage, @parent

        @invitation = PallasTrade::Invitation.new(permitted_params)
        @invitation.resource = @parent
        @invitation.inviter = try_pallastrade_current_user

        if @invitation.save
          respond_to do |format|
            format.html { redirect_to PallasTrade.admin_invitations_path, notice: flash_message_for(@invitation, :successfully_created) }
            format.turbo_stream
          end
        else
          render :new, status: :unprocessable_content
        end
      end

      # GET /admin/invitations/:id?token=:token
      def show
        decoded_id = PallasTrade::Invitation.decode_prefixed_id(params[:id])
        @invitation = PallasTrade::Invitation.pending.not_expired.find_by!(id: decoded_id, token: params[:token])
        @parent = @invitation.resource

        if try_pallastrade_current_user.present?
          unless @invitation.invitee == try_pallastrade_current_user
            raise ActiveRecord::RecordNotFound
          end
        elsif @invitation.invitee.present?
          store_location
          try_to_redirect_to_login_path
        else
          redirect_to PallasTrade.new_admin_admin_user_path(token: @invitation.token), status: :see_other
        end
      rescue ActiveRecord::RecordNotFound
        render :expired, status: :not_found
      end

      # PUT /admin/invitations/:id/accept
      def accept
        @invitation = try_pallastrade_current_user.invitations.pending.not_expired.find_by_prefix_id!(params[:id])

        authorize! :accept, @invitation

        @invitation.accept!
        redirect_to PallasTrade.admin_path, notice: PallasTrade.t('invitation_accepted')
      end

      # PUT /admin/invitations/:id/resend
      def resend
        @invitation = scope.find_by_prefix_id!(params[:id])
        @invitation.resend!
        redirect_back fallback_location: PallasTrade.admin_invitations_path, notice: PallasTrade.t('invitation_resent')
      end

      # DELETE /admin/invitations/:id
      def destroy
        authorize! :destroy, @invitation

        @invitation.destroy
        redirect_back fallback_location: PallasTrade.admin_invitations_path, notice: flash_message_for(@invitation, :successfully_removed)
      end

      private

      def load_invitation
        @invitation = scope.find_by_prefix_id!(params[:id])
      end

      def load_parent
        @parent = current_store
      end

      def scope
        PallasTrade::Invitation.accessible_by(current_ability).where(resource: @parent)
      end

      def load_roles
        @roles = PallasTrade::Role.accessible_by(current_ability)
      end

      def permitted_params
        params.require(:invitation).permit(PallasTrade::PermittedAttributes.invitation_attributes)
      end

      def choose_layout
        action_name == 'show' ? 'pallastrade/minimal' : 'pallastrade/admin_settings'
      end

      def model_class
        PallasTrade::Invitation
      end
    end
  end
end
