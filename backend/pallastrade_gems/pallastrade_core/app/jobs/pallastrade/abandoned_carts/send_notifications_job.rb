# frozen_string_literal: true

module PallasTrade
  module AbandonedCarts
    # Scans stores for abandoned carts (P0-3, 2026-08-18):
    # incomplete orders that have an email, at least one line item and whose
    # last_activity_at is older than the threshold. Sends one recovery email per
    # (cart, email) — the unique index on AbandonedCartNotification makes it
    # idempotent across repeated runs.
    #
    # Scheduled by sidekiq-cron (config/sidekiq.yml).
    class SendNotificationsJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      def perform(threshold_hours: 24, store_id: nil)
        stores = PallasTrade::Store.all
        stores = stores.where(id: store_id) if store_id
        stores.find_each { |store| send_for_store(store, threshold_hours) }
      end

      private

      def send_for_store(store, threshold_hours)
        return unless abandoned_cart_recovery_enabled?(store)

        since = Time.current - threshold_hours.to_i.hours
        store.carts.abandoned(since).find_each do |cart|
          next unless cart.line_items.exists?
          next if store.abandoned_cart_notifications.exists?(cart_id: cart.id)

          notification = store.abandoned_cart_notifications.create!(cart: cart, email: cart.email)
          AbandonedCartMailer.recovery_email(notification).deliver_later
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn("Abandoned cart notification skipped for cart #{cart.id}: #{e.message}")
        end
      end

      def abandoned_cart_recovery_enabled?(store)
        store.preferences['email_scenario_abandoned_cart.recovery_email'] != false
      end
    end
  end
end
