# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::Compare` —— 锁汇快照 × 结算台账 → **结算汇率对比**（逐笔）。
#
# 结算汇率来源（优先级，唯一口径）：
#   ① 结算行报文显式汇率 `payout_line.raw['fx_rate']` → `settlement_source = 'provider_reported'`；
#   ② 由结算金额推导 `line.gross_amount / payment.amount`（结算币种 == 快照 base 且订单币种 == 快照 quote）
#      → `'implied'`；
#   ③ 两者都拿不到（无结算行 / 币种对不上 / 金额不可用）→ `variance_status = 'undetermined'` + signal（**不猜**）。
#
# 判定：`variance_bips = round((settlement_rate − effective_rate) / effective_rate × 10000)`；
#   `|bips| <= tolerance` → `matched`；否则 `mismatch`；无结算数据 → 保持 `pending`（等结算落地）。
#
# 扫描集合（每次运行）：
#   * 期间内 `pending` / `undetermined` 的快照（等结算或等补录汇率）；
#   * 已是 `mismatch` 但**结算行在上次比对之后被改动**（如重新导入修正的结算单）→ 复算，允许翻回 `matched`。
#
# 铁律：**零资金副作用** —— 只写快照对比结果 + 案例 + 审计；不触碰 Payment/Refund/账本/库存/订单金额，不外呼。
module PallasTrade
  module Currencies
    module Fx
      class Compare
        prepend PallasTrade::ServiceModule::Base

        MAX_SNAPSHOTS = 5_000
        DETAIL_LIMIT = 50

        # @param store [PallasTrade::Store]
        # @param from [Time, String, nil] 期间（左闭右开；给定则只扫该期间锁定的快照）
        # @param to [Time, String, nil]
        # @param snapshots [Array<PallasTrade::FxSnapshot>, nil] 显式集合（后台「重新比对」用）
        # @param tolerance_bips [Integer, nil] 覆盖店铺策略容差
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success(Hash)
        def call(store:, from: nil, to: nil, snapshots: nil, tolerance_bips: nil, now: Time.current,
                 sync_cases: true, detail: true)
          return failure(nil, 'Store is required') if store.nil?

          policy = PallasTrade::Currencies::Fx::Policy.for_store(store)
          tolerance = (tolerance_bips || policy[:variance_tolerance_bips]).to_i
          candidates = snapshots || scan(store, from, to)
          truncated = candidates.size >= MAX_SNAPSHOTS
          candidates = candidates.first(MAX_SNAPSHOTS)

          context = load_context(candidates)
          results = candidates.map { |snapshot| evaluate(snapshot, context, tolerance, now) }

          counters = tally(results)
          case_outcome = sync_cases ? sync(candidates, store, policy, now) : { opened: [], touched: [], closed: [] }

          success(counters.merge(
                    cases: case_outcome,
                    tolerance_bips: tolerance,
                    truncated: truncated,
                    details: detail ? results.compact.first(DETAIL_LIMIT) : []
                  ))
        end

        private

        def scan(store, from, to)
          scope = PallasTrade::FxSnapshot.for_store(store).awaiting_comparison
          scope = scope.locked_between(parse_time(from), parse_time(to)) if from.present? && to.present?
          candidates = scope.recent_first.limit(MAX_SNAPSHOTS).to_a
          candidates + stale_mismatches(store, candidates)
        end

        # 已被判 mismatch、但结算行在上次比对之后被改动 → 复算（修正后应翻回 matched 并自动销案）
        def stale_mismatches(store, already)
          scope = PallasTrade::FxSnapshot.for_store(store).mismatched
          known = already.map(&:id)
          scope = scope.where.not(id: known) if known.any?
          rows = scope.recent_first.limit(MAX_SNAPSHOTS).to_a
          return [] if rows.empty?

          lines = payout_lines_for_payment_ids(rows.map(&:payment_id).compact)
          rows.select do |snapshot|
            line = lines[snapshot.payment_id]
            line.present? && (snapshot.compared_at.nil? || line.updated_at > snapshot.compared_at)
          end
        end

        # 批量装载（各一次查询）：已完成支付 / 结算行 / 订单币种
        def load_context(candidates)
          order_ids = candidates.map(&:order_id).compact.uniq
          payments = PallasTrade::Payment.completed.where(order_id: order_ids).order(:id).to_a
          payments_by_order = payments.group_by(&:order_id).transform_values(&:last)
          lines = payout_lines_for_payment_ids(payments.map(&:id))
          orders = PallasTrade::Order.where(id: order_ids).index_by(&:id)

          { payments_by_order: payments_by_order, lines: lines, orders: orders }
        end

        def payout_lines_for_payment_ids(payment_ids)
          ids = Array(payment_ids).compact.uniq
          return {} if ids.empty?

          PallasTrade::PayoutLine.where(payment_id: ids, refund_id: nil)
                                 .order(:id)
                                 .to_a
                                 .group_by(&:payment_id)
                                 .transform_values(&:last)
        end

        # @return [Hash, nil] 每条快照的对比结果
        def evaluate(snapshot, context, tolerance, now)
          payment = context[:payments_by_order][snapshot.order_id]
          line = payment.present? ? context[:lines][payment.id] : nil

          if payment.nil? || line.nil?
            return persist(snapshot, state: 'pending', signals: ['settlement_pending'], now: now)
          end

          rate, source = settlement_rate(snapshot, payment, line)
          if rate.nil?
            return persist(snapshot, state: 'undetermined', signals: [@last_signal || 'settlement_rate_unavailable'],
                           payment: payment, line: line, now: now)
          end

          effective = snapshot.effective_rate.to_d
          bips = ((rate - effective) / effective * 10_000).round
          state = bips.abs <= tolerance ? 'matched' : 'mismatch'

          persist(snapshot, state: state, signals: @last_signal ? [@last_signal] : [], payment: payment, line: line,
                           settlement_rate: rate, settlement_source: source, bips: bips, now: now)
        end

        # @return [Array(BigDecimal, String), Array(nil, nil)]
        def settlement_rate(snapshot, payment, line)
          @last_signal = nil

          explicit = line.raw.is_a?(Hash) ? line.raw['fx_rate'] : nil
          explicit = explicit.is_a?(Hash) ? explicit.values.first : explicit
          decimal = decimal_or_nil(explicit)
          return [decimal.round(10), 'provider_reported'] if decimal&.positive?

          unless line.currency.to_s.upcase == snapshot.base_currency.to_s.upcase
            @last_signal = 'currency_pair_mismatch'
            return [nil, nil]
          end

          amount = payment.amount.to_d
          if amount <= 0 || line.gross_amount.to_d <= 0
            @last_signal = 'settlement_rate_unavailable'
            return [nil, nil]
          end

          @last_signal = 'implied_rate'
          [(line.gross_amount.to_d / amount).round(10), 'implied']
        end

        def decimal_or_nil(value)
          return nil if value.blank?
          return value if value.is_a?(Numeric)

          decimal = BigDecimal(value.to_s)
          decimal.positive? ? decimal : nil
        rescue ArgumentError, TypeError
          nil
        end

        def persist(snapshot, state:, signals:, now:, payment: nil, line: nil, settlement_rate: nil,
                    settlement_source: nil, bips: nil)
          expected = payment.present? ? (payment.amount.to_d * snapshot.effective_rate.to_d).round(2) : nil

          snapshot.update!(
            variance_status: state,
            settlement_rate: settlement_rate,
            settlement_source: settlement_source,
            settlement_currency: line&.currency,
            settled_gross_amount: line&.gross_amount,
            variance_bips: bips,
            payment_id: payment&.id || snapshot.payment_id,
            compared_at: now,
            occurrences: snapshot.occurrences.to_i + 1,
            signals: (snapshot.signals || {}).merge('list' => signals.compact.uniq),
            metadata: (snapshot.metadata || {}).merge(
              'expected_settled_amount' => expected&.to_s,
              'payout_line_id' => line&.id,
              'payout_id' => line&.payout_id
            )
          )

          {
            snapshot_id: snapshot.id,
            order_id: snapshot.order_id,
            order_number: snapshot.metadata['order_number'],
            variance_status: state,
            variance_bips: bips,
            settlement_rate: settlement_rate&.to_s,
            settlement_source: settlement_source,
            effective_rate: snapshot.effective_rate.to_s,
            signals: signals.compact.uniq
          }
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error("[Fx::Compare] snapshot #{snapshot.id} not updated: #{e.message}")
          nil
        end

        def tally(results)
          rows = results.compact
          {
            scanned: rows.size,
            compared: rows.count { |row| %w[matched mismatch].include?(row[:variance_status]) },
            matched: rows.count { |row| row[:variance_status] == 'matched' },
            mismatched: rows.count { |row| row[:variance_status] == 'mismatch' },
            pending: rows.count { |row| row[:variance_status] == 'pending' },
            undetermined: rows.count { |row| row[:variance_status] == 'undetermined' }
          }
        end

        def sync(candidates, store, policy, now)
          return { opened: [], touched: [], closed: [] } unless policy[:auto_reconcile]

          touched = PallasTrade::FxSnapshot.where(id: candidates.map(&:id)).to_a
          PallasTrade::Currencies::Fx::SyncCases.call(store: store, snapshots: touched, now: now).value ||
            { opened: [], touched: [], closed: [] }
        end

        def parse_time(value)
          return nil if value.blank?
          return value if value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
