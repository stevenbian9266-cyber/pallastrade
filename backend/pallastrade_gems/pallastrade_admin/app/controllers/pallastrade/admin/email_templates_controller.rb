# frozen_string_literal: true

module PallasTrade
  module Admin
    # Email templates CRUD (Email → Templates). Content editing with
    # {placeholder} substitution and a live preview.
    class EmailTemplatesController < ResourceController
      include PallasTrade::Admin::TableConcern
      include PallasTrade::Admin::EmailsBreadcrumbConcern
      add_breadcrumb PallasTrade.t('admin.emails.templates'), :admin_email_templates_path

      before_action :add_breadcrumb_for_template, only: [:show, :edit, :update]

      def preview
        @object = find_object
        @context = preview_context
        respond_to do |format|
          format.html { render partial: 'preview', locals: { object: @object, context: @context } }
        end
      end

      def test_send
        @object = find_object
        to = params[:to_email].presence || current_admin_user.email

        if @object.test_send(to, preview_context)
          flash[:success] = PallasTrade.t('admin.emails.test_sent', email: to)
        else
          flash[:error] = PallasTrade.t('admin.emails.test_send_failed')
        end
        redirect_to PallasTrade.admin_email_template_path(@object)
      end

      private

      def model_class
        PallasTrade::EmailTemplate
      end

      def scope
        current_store.email_templates
      end

      def object_name
        'email_template'
      end

      def permitted_resource_params
        params.require(:email_template).permit(:key, :name, :subject, :body_html, :body_text, :placeholders, :active)
      end

      def location_after_save
        PallasTrade.admin_email_templates_path
      end

      def location_after_destroy
        PallasTrade.admin_email_templates_path
      end

      def find_object
        scope.find_by_prefix_id(params[:id]) || scope.find(params[:id])
      end

      def add_breadcrumb_for_template
        return unless @object.present? && @object.persisted?
        add_breadcrumb @object.name, PallasTrade.admin_email_template_path(@object)
      end

      # Sample context used for preview / test send. Real values are supplied
      # by each mailer; here we demonstrate placeholder substitution.
      def preview_context
        {
          order_number: 'R123456789',
          store_name: current_store.name,
          product_name: 'Example Product',
          customer_name: 'Test Customer'
        }
      end
    end
  end
end
