# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B2
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # OpsReport —— 争议**运营报表**（FR-006）。
    #
    # 铁律：
    #   - **只读**：不做任何写入（无审计、无事件、不 touch `Dispute`），不触网、不调 provider；
    #   - **不推断**：金额/币种不可比时**不猜**（mixed currency → 金额置 nil + degraded 说明）；
    #   - **状态词汇取自模型常量**（`Dispute::TERMINAL_STATES`），不在报表里另立一套口径；
    #   - 输出为纯 Hash，可由控制台/rake 复用（本服务不认识任何视图）。
    #
    # 指标口径（写死在文档里，避免"同一指标两种算法"）：
    #   - 胜诉率 `win_rate` = won / (won + lost)（分母为 0 → nil，不用 0 伪装）；
    #   - 时限达成 `met_rate` = 在 `evidence_due_at` 前已提交 / 有截止时间的争议数；
    #   - 处理时长 = `resolved_at - created_at`（仅终态且有 `resolved_at` 的记录），给平均/中位/最快/最慢。
    class OpsReport
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_WINDOW_DAYS = 90
      UNKNOWN_REASON = 'unknown'

      # @param store [PallasTrade::Store]
      # @param from [Time, nil] 窗口起点（含）
      # @param to [Time, nil] 窗口终点（含）
      # @param provider [String, nil] 仅看某 provider
      # @param window_days [Integer, nil] 未显式给 from/to 时的默认窗口天数
      # @return [PallasTrade::ServiceModule::Result] success(report_hash)
      def call(store:, from: nil, to: nil, provider: nil, window_days: nil)
        return success(degraded_envelope('store_missing')) if store.nil?

        range = build_range(from, to, window_days)
        scope = PallasTrade::Dispute.for_store(store)
        scope = scope.where(provider: provider.to_s) if provider.present?
        scope = scope.where(created_at: range) if range

        success(build_report(scope, store: store, provider: provider, range: range))
      rescue StandardError => e
        success(degraded_envelope("report_unavailable:#{e.class}"))
      end

      private

      # 降级信封：字段齐全但全部为"不可用"（nil/0/空），并在 `degraded` 说明原因 —— 不猜、不 500
      def degraded_envelope(reason)
        {
          scope: { store_id: nil, provider: nil, from: nil, to: nil, window_days: nil },
          totals: { disputes: 0, active: 0, terminal: 0, needs_attention: 0 },
          states: {},
          outcomes: { won: 0, lost: 0, accepted: 0, expired: 0, closed: 0, decided: 0, win_rate: nil },
          by_reason: [],
          deadlines: { with_deadline: 0, met: 0, submitted_late: 0, not_submitted: 0, no_deadline: 0, met_rate: nil },
          handling: { resolved_count: 0, average_days: nil, median_days: nil, fastest_days: nil, slowest_days: nil },
          money: { currency: nil, mixed_currency: false, disputed_amount: nil, fee_amount: nil, currencies: [] },
          degraded: [reason]
        }
      end

      def build_range(from, to, window_days)
        return nil if window_days == :all

        end_at = to.presence
        start_at = from.presence
        start_at = (window_days.presence || DEFAULT_WINDOW_DAYS).to_i.days.ago if start_at.nil? && end_at.nil?
        return nil if start_at.nil? && end_at.nil?
        return (start_at..) if end_at.nil?
        return (..end_at) if start_at.nil?

        start_at..end_at
      end

      def build_report(scope, store:, provider:, range:)
        state_counts = scope.group(:state).count
        outcome_counts = scope.group(:outcome).count
        won = outcome_counts['won'].to_i
        lost = outcome_counts['lost'].to_i
        budget = scope.where.not(resolved_at: nil)

        {
          scope: {
            store_id: store.id, provider: provider.presence,
            from: range&.begin, to: range&.end,
            window_days: range ? nil : DEFAULT_WINDOW_DAYS
          },
          totals: {
            disputes: scope.count,
            active: scope.active.count,
            terminal: scope.terminal.count,
            needs_attention: scope.needs_attention.count
          },
          states: state_counts,
          outcomes: {
            won: won, lost: lost, accepted: outcome_counts['accepted'].to_i,
            expired: outcome_counts['expired'].to_i, closed: outcome_counts['closed'].to_i,
            decided: won + lost,
            win_rate: rate(won, won + lost)
          },
          by_reason: by_reason(scope),
          deadlines: deadlines(scope),
          handling: handling(budget),
          money: money(scope),
          degraded: []
        }
      end

      def by_reason(scope)
        expression = reason_expression
        totals = scope.group(expression).count
        decided = scope.where(outcome: %w[won lost]).group(expression).group(:outcome).count
        wins = scope.where(outcome: 'won').group(expression).count
        losses = scope.where(outcome: 'lost').group(expression).count

        totals.map do |reason, total|
          row_won = wins[reason].to_i
          row_lost = losses[reason].to_i
          row_decided = decided[[reason, 'won']].to_i + decided[[reason, 'lost']].to_i
          {
            reason: reason.presence || UNKNOWN_REASON,
            total: total,
            won: row_won,
            lost: row_lost,
            decided: row_decided,
            win_rate: rate(row_won, row_decided)
          }
        end.sort_by { |row| [-row[:total], row[:reason]] }
      end

      def deadlines(scope)
        with_deadline = scope.where.not(evidence_due_at: nil)
        total = with_deadline.count
        met = with_deadline.where.not(evidence_submitted_at: nil)
                           .where('pallastrade_disputes.evidence_submitted_at <= pallastrade_disputes.evidence_due_at')
                           .count
        submitted_late = with_deadline.where.not(evidence_submitted_at: nil).count - met

        {
          with_deadline: total,
          met: met,
          submitted_late: submitted_late,
          not_submitted: total - met - submitted_late,
          no_deadline: scope.where(evidence_due_at: nil).count,
          met_rate: rate(met, total)
        }
      end

      def handling(scope)
        pairs = scope.pluck(:created_at, :resolved_at).select { |(created, resolved)| created && resolved }
        return { resolved_count: 0, average_days: nil, median_days: nil, fastest_days: nil, slowest_days: nil } if pairs.empty?

        seconds = pairs.map { |(created, resolved)| (resolved - created).to_f }.sort
        {
          resolved_count: seconds.size,
          average_days: round(seconds.sum / seconds.size / 86_400.0),
          median_days: round(median(seconds) / 86_400.0),
          fastest_days: round(seconds.first / 86_400.0),
          slowest_days: round(seconds.last / 86_400.0)
        }
      end

      def money(scope)
        currencies = scope.where.not(currency: [nil, '']).distinct.pluck(:currency)
        if currencies.size > 1
          return { currency: nil, mixed_currency: true, disputed_amount: nil, fee_amount: nil,
                   currencies: currencies.sort }
        end

        {
          currency: currencies.first&.to_s,
          mixed_currency: false,
          disputed_amount: scope.sum(:amount).to_f,
          fee_amount: scope.sum(:fee_amount).to_f,
          currencies: currencies.sort
        }
      end

      def rate(numerator, denominator)
        return nil if denominator.to_i.zero?

        round(numerator.to_f / denominator.to_f, 4)
      end

      def median(sorted)
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end

      def round(value, digits = 2)
        value.nil? ? nil : value.to_f.round(digits)
      end

      # 仅当 `reason` 与 `network_reason_code` 都为空时归入 unknown（不把空串当 reason）
      def reason_expression
        Arel.sql("COALESCE(NULLIF(pallastrade_disputes.reason, ''), NULLIF(pallastrade_disputes.network_reason_code, ''))")
      end
    end
  end
end
