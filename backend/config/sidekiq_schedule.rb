# P0-3 (2026-08-18): scheduled abandoned-cart recovery scan.
# Loaded by config/initializers/pallastrade_sidekiq_cron.rb inside the
# Sidekiq server process; entries are class + cron expression.
PALLAS_CART_SCHEDULE = [
  {
    name: 'abandoned_cart_recovery',
    class: 'PallasTrade::AbandonedCarts::SendNotificationsJob',
    cron: '*/5 * * * *',
    queue: 'default',
    args: [{ 'threshold_hours' => 24 }]
  }
].freeze
