# frozen_string_literal: true

# P0-3 (2026-08-18): register scheduled jobs (abandoned-cart recovery scan)
# with sidekiq-cron inside the Sidekiq server process. Schedule lives in
# config/sidekiq_schedule.rb.
if defined?(Sidekiq::Cron::Job) && Sidekiq.server?
  # config/sidekiq_schedule.rb lives outside config/initializers/, so it is
  # NOT auto-loaded by Rails — require it explicitly to define the schedule.
  require Rails.root.join('config/sidekiq_schedule')

  Rails.application.config.after_initialize do
    begin
      PALLAS_CART_SCHEDULE.each do |entry|
        Sidekiq::Cron::Job.create(
          name: entry[:name],
          cron: entry[:cron],
          class: entry[:class],
          queue: entry[:queue],
          args: entry[:args] || []
        ) unless Sidekiq::Cron::Job.find(entry[:name])
      end
    rescue StandardError => e
      Rails.logger.warn("[sidekiq-cron] schedule registration skipped: #{e.message}")
    end
  end
end
