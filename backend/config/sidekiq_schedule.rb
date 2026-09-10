# P0-3 (2026-08-18): scheduled abandoned-cart recovery scan.
# TXN-P2-7 slice2 (2026-09-05): conservative CommerceTransaction recovery sweeper.
# INV-P3-1 (2026-09-05): StockReservation TTL expiration（RESERVED → EXPIRED）。
# Loaded by config/initializers/pallastrade_sidekiq_cron.rb inside the
# Sidekiq server process; entries are class + cron expression.
PALLAS_CART_SCHEDULE = [
  {
    name: 'abandoned_cart_recovery',
    class: 'PallasTrade::AbandonedCarts::SendNotificationsJob',
    cron: '*/5 * * * *',
    queue: 'default',
    args: [{ 'threshold_hours' => 24 }]
  },
  {
    name: 'transaction_recovery_sweeper',
    class: 'PallasTrade::Transactions::RecoverSweeperJob',
    cron: '*/5 * * * *',
    queue: 'default',
    args: [{ 'threshold_hours' => 1 }]
  },
  {
    name: 'stock_reservation_expiry',
    class: 'PallasTrade::StockReservations::ExpireJob',
    cron: '*/5 * * * *',
    queue: 'default'
  },
  # PRD-20260910-promo-batch3b: 促销核销 reserved 行的 TTL 出口（保守：有支付证据不释放）。
  {
    name: 'promotion_redemption_expiry',
    class: 'PallasTrade::Promotions::Redemption::ExpireSweeperJob',
    cron: '*/5 * * * *',
    queue: 'default'
  },
  # FIN-P4 review 批1 (2026-09-06, bugfix C6): 注册 reconciliation sweeper —— 自动 reconcile +
  # journal-missing 幂等补记闭环（此前仅在手动 rake，部署中从不运行）。保守：仅 enqueue 补记。
  {
    name: 'financial_reconcile_sweeper',
    class: 'PallasTrade::Reconciliations::ReconcileSweeperJob',
    cron: '*/10 * * * *',
    queue: 'default'
  },
  # REV-P6-6 (2026-09-08): 注册 refund recovery sweeper —— 保守自动收敛 requested（从未执行）/processing
  # （超时）退款；ambiguous/manual/failed 仅计数 + warn（人工介入）。enqueue RecoverJob 幂等。
  {
    name: 'refund_recovery_sweeper',
    class: 'PallasTrade::Refunds::RecoverSweeperJob',
    cron: '*/5 * * * *',
    queue: 'default',
    args: [{ 'requested_hours' => 1, 'processing_hours' => 6 }]
  },
  # REV-P6-8i (2026-09-09): 注册 reverse commerce recover sweeper —— 周期扫描 restock-AMBIGUOUS
  # （accepted+eligible+无 StockMovement）订单并 enqueue 幂等 ReverseCommerce::RecoverJob（capped 防风暴）。
  {
    name: 'reverse_commerce_recover_sweeper',
    class: 'PallasTrade::ReverseCommerce::RecoverSweeperJob',
    cron: '*/5 * * * *',
    queue: 'default',
    args: [{ 'max_enqueues' => 20 }]
  }
].freeze
