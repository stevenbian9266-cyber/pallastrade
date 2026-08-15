# frozen_string_literal: true

module PallasTrade
  module Admin
    # Inbox & feedback (Email → Inbox): complaints, feedback, inquiries and
    # inbound replies, with status flow (pending → in_progress → resolved).
    class ContactMessagesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      def resolve
        @object = find_object
        @object.update!(status: 'resolved')
        flash[:success] = PallasTrade.t('admin.emails.message_resolved')
        redirect_to PallasTrade.admin_contact_messages_path
      end

      private

      def model_class
        PallasTrade::ContactMessage
      end

      def scope
        current_store.contact_messages.recent
      end

      def object_name
        'contact_message'
      end

      def permitted_resource_params
        params.require(:contact_message).permit(:kind, :status, :name, :email, :subject, :body)
      end

      def location_after_save
        PallasTrade.admin_contact_messages_path
      end

      def find_object
        scope.find_by_prefix_id(params[:id]) || scope.find(params[:id])
      end
    end
  end
end
