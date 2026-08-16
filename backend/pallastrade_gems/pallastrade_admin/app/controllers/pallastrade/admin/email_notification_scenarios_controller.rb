# frozen_string_literal: true

module PallasTrade
  module Admin
    # Email notification scenarios (Email → Notification scenarios).
    # Each scenario maps to a transactional email (mailer.action) and can be
    # toggled on/off per store, plus a test-send button. Toggle state is
    # persisted in store preferences (preferred_email_scenario_<key>).
    class EmailNotificationScenariosController < PallasTrade::Admin::BaseController
      # 面包屑由导航自动推导（P3）：Emails → Notification Scenarios

      before_action :load_store

      # The canonical scenario registry. `key` matches the EmailTemplate key and
      # the mailer.action that sends the email. Extend as new emails are added.
      SCENARIOS = [
        { key: 'order.confirm_email',                name: 'admin.emails.scenarios.order_confirmation' },
        { key: 'order.payment_link_email',           name: 'admin.emails.scenarios.payment_link' },
        { key: 'order.cancel_email',                 name: 'admin.emails.scenarios.order_canceled' },
        { key: 'shipment.shipped_email',             name: 'admin.emails.scenarios.shipment_shipped' },
        { key: 'reimbursement.reimbursement_email',  name: 'admin.emails.scenarios.reimbursement' },
        { key: 'back_in_stock.back_in_stock',        name: 'admin.emails.scenarios.back_in_stock' },
        { key: 'customer.password_reset_email',      name: 'admin.emails.scenarios.password_reset' },
        { key: 'newsletter.email_confirmation',      name: 'admin.emails.scenarios.newsletter_confirmation' }
      ].freeze

      def index
        templates_by_key = current_store.email_templates.where(key: SCENARIOS.map { |s| s[:key] }).index_by(&:key)
        @scenarios = SCENARIOS.map do |scenario|
          scenario.merge(
            enabled: scenario_enabled?(scenario[:key]),
            template: templates_by_key[scenario[:key]]
          )
        end
      end

      def update
        updated = SCENARIOS.to_h { |s| [s[:key], params[:enabled].to_a.include?(s[:key])] }
        updated.each do |key, enabled|
          @store.preferences["email_scenario_#{key}"] = enabled
        end
        @store.save!
        flash[:success] = PallasTrade.t('admin.emails.scenarios_saved')
        redirect_to PallasTrade.admin_email_notification_scenarios_path
      end

      def test_send
        key = params[:key]
        scenario = SCENARIOS.find { |s| s[:key] == key }
        if scenario.nil?
          flash[:error] = PallasTrade.t('admin.emails.scenario_not_found')
        elsif send_test_email(scenario)
          flash[:success] = PallasTrade.t('admin.emails.test_sent', email: current_admin_user.email)
        else
          flash[:error] = PallasTrade.t('admin.emails.test_send_failed')
        end
        redirect_to PallasTrade.admin_email_notification_scenarios_path
      end

      private

      def load_store
        @store = current_store
      end

      def scenario_enabled?(key)
        @store.preferences["email_scenario_#{key}"].to_s != 'false'
      end

      def send_test_email(scenario)
        to = current_admin_user.email
        context = test_context

        template = current_store.email_templates.find_by(key: scenario[:key])
        if template
          subject = template.render_subject(context)
          body_html = template.render_body(:html, context)
          body_text = template.render_body(:text, context)
        else
          subject = "#{PallasTrade.t('admin.emails.test_subject', store_name: current_store.name)} — #{PallasTrade.t(scenario[:name])}"
          body = PallasTrade.t('admin.emails.test_body')
          body_html = "<p>#{body}</p><p>#{PallasTrade.t(scenario[:name])}</p>"
          body_text = "#{body}\n#{PallasTrade.t(scenario[:name])}"
        end

        PallasTrade::TestMailer.test_email(
          to: to,
          subject: subject,
          body_html: body_html,
          body_text: body_text,
          store: current_store
        ).deliver_now
        true
      rescue StandardError => e
        Rails.logger.warn("[email_scenarios] test send failed for #{scenario[:key]}: #{e.message}")
        false
      end

      # Sample placeholder values for scenario test sends.
      def test_context
        {
          order_number: 'R123456789',
          store_name: current_store.name,
          product_name: 'Example Product',
          customer_name: 'Test Customer',
          email: current_admin_user.email
        }
      end
    end
  end
end
