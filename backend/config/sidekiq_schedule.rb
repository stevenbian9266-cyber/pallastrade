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
  },
  # DSP-P7-5 (2026-09-12): 注册争议证据期限扫描 —— **只提示不决策**（不提交证据/不接受争议/不退款）；
  # 每日 01:00 扫一次（避免每小时告警噪音），告警 payload 携带 P7-4 的 missing_evidence 便于应诉准备。
  {
    name: 'dispute_deadline_sweep',
    class: 'PallasTrade::Disputes::DeadlineSweeperJob',
    cron: '0 1 * * *',
    queue: 'default',
    args: [{ 'window_hours' => 72 }]
  },
  # DSP-P7-6 (2026-09-12): 注册争议收敛 sweeper —— **只修事实、不做资金决策**（不重扣款/不自动退款）：
  # provider 权威状态单调收敛 + journal_missing 幂等补记 + 冲突/缺证据交人工（manual_review）。
  # 每日 01:30（错开 01:00 的期限扫描）；limit 50 有界（最多 50 次 provider 只读调用）。
  {
    name: 'dispute_recovery_sweep',
    class: 'PallasTrade::Disputes::RecoverSweeperJob',
    cron: '30 1 * * *',
    queue: 'default',
    args: [{ 'limit' => 50, 'verify_after_hours' => 24 }]
  },
  # G-7 (2026-09-16, PRD-20260916-catalog-health-trend-snapshot): 注册 Catalog Health 每日快照 ——
  # **只写快照表**（不碰商品/媒体/翻译/redirect，不发事件）：每店每日一行/issue，
  # 供工作台读趋势（口径复用 `CatalogHealth::Issues.count`，保持"计数==列表"）。
  # 每日 02:00（错开 01:00 期限扫描 / 01:30 收敛 sweeper）；store_limit 有界。
  {
    name: 'catalog_health_snapshot',
    class: 'PallasTrade::CatalogHealth::SnapshotSweeperJob',
    cron: '0 2 * * *',
    queue: 'default',
    args: [{ 'store_limit' => 500 }]
  },
  # D13 切片4 (2026-09-16): 注册汇率对比巡检 —— **只做结算差核算**（不改订单/支付金额、不退款、不写账本、
  # 零 provider 外呼）：锁汇快照 × 结算台账 → 偏差 bips → 超容差进入对账队列（kind=fx），
  # 恢复一致自动销案。每 30 分钟；扫描期间 90 天（有界）。
  {
    name: 'fx_rate_compare_sweep',
    class: 'PallasTrade::Currencies::Fx::CompareSweeperJob',
    cron: '*/30 * * * *',
    queue: 'default',
    args: [{ 'lookback_days' => 90 }]
  },
  # PAY-D11-1 (2026-09-16): 注册支付熔断巡检 —— **只读聚合 + metadata 写，零资金副作用**
  # （不取消会话/不改支付/订单/库存，零 provider 调用）：小时级判定失败率阈值 → 入口级软置灰；
  # 同时执行自动置灰的到期恢复（手动置灰 `manual: true` 不自动恢复，必须人工解除）。
  {
    name: 'payment_circuit_breaker_sweep',
    class: 'PallasTrade::Payments::CircuitBreaker::SweepJob',
    cron: '15 * * * *',
    queue: 'default'
  },
  # D14 切片3 (2026-09-16): 拒付率阈值巡检 —— **只读统计 + 只写预警台账/审计，零资金副作用**
  # （不改支付/订单/退款/账本/库存/争议状态，零 provider 调用）：逐店铺算「按卡组织的笔数比 + 金额比」
  # → 达到阈值 80%（可配）落 approaching、达到阈值落 breached → 档位升级时发布 `dispute.rate_threshold`。
  # 每小时一次（偏移 45 分），避免与既有巡检同点竞争。
  {
    name: 'dispute_rate_alert_sweep',
    class: 'PallasTrade::Disputes::RateAlertSweeperJob',
    cron: '45 * * * *',
    queue: 'default'
  }
].freeze
