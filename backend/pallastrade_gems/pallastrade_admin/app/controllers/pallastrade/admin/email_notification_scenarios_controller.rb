# frozen_string_literal: true

module PallasTrade
  module Admin
    # Email notification scenarios (Email → Notification scenarios).
    # Each scenario maps to a transactional email (mailer.action) and can be
    # toggled on/off per store, plus a test-send button. Toggle state is
    # persisted in store preferences (preferred_email_scenario_<key>).
    class EmailNotificationScenariosController < PallasTrade::Admin::BaseController
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
        @scenarios = SCENARIOS.map do |scenario|
          scenario.merge(
            enabled: scenario_enabled?(scenario[:key]),
            template: current_store.email_templates.find_by(key: scenario[:key])
          )
        end
        add_breadcrumb PallasTrade.t(:emails), PallasTrade.admin_emails_path
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
        mailer_class, action = scenario[:key].split('.')
        klass = "PallasTrade::#{mailer_class.camelize}Mailer".constantize
        return false unless klass.respond_to?(action)

        # Only mailers whose action accepts a single record can be tested here.
        # Pass a lightweight dummy via a test payload where possible.
        case scenario[:key]
        when 'back_in_stock.back_in_stock'
          sub = current_store.back_in_stock_subscriptions.first
          return false if sub.nil?
          klass.public_send(action, sub).deliver_now
        else
          return false
        end
        true
      rescue StandardError => e
        Rails.logger.warn("[email_scenarios] test send failed for #{scenario[:key]}: #{e.message}")
        false
      end
    end
  end
end
