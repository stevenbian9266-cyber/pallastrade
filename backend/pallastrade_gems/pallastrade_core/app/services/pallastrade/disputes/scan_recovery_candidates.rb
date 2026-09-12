# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-6 (PRD-20260912-payments-dsp-p7-6-dispute-recovery)
#
# Disputes::ScanRecoveryCandidates —— 收敛候选的**本地预筛**（源计划 §47 sweeper 输入）。
#
# 设计要点：
#   - **零 provider I/O**：三类候选全部用本地 SQL 判定（是否「需要看一眼 provider」交执行期决定），
#     因此扫描本身可安全高频调用；provider 只读调用由 `RecoverSweeperJob` 按候选类型逐条触发。
#   - 三类 selection（封闭枚举，按优先级去重，一条 dispute 只取最高优先级）：
#       1. `attention`    `attention_reason` 非空 —— 已明确需人工/待收敛的行
#       2. `journal_gap`  有 funds 时间戳但无对应账行（**纯 SQL** 反连接）—— P7-3 对账缺口的可修子集
#       3. `stale_active` 非终态且 `updated_at` 早于 `verify_after_hours` —— 可能漏事件的活跃争议
#   - 排序：attention → journal_gap → stale_active，组内 `updated_at` 升序 + `id` 稳定；`limit` 截断。
#
# 只读边界：零写、零网络。返回项携带 AR 记录（`dispute:`，供执行期复用，避免二次查询）
#   与 prefixed id（`dispute_id:`，供日志/事件），与 `Reconciliations::ReconcileDispute` 同风格。
module PallasTrade
  module Disputes
    class ScanRecoveryCandidates
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_LIMIT = 50
      DEFAULT_VERIFY_AFTER_HOURS = 24

      SELECTIONS = %w[attention journal_gap stale_active].freeze

      # funds 时间戳 → 期望账行类型（P7-3 `ReconcileDispute::EXPECTATION_BY_ATTRIBUTE` 的反向映射）
      FUNDS_ATTRIBUTE_BY_ENTRY_TYPE = {
        'DISPUTE_FUNDS_WITHDRAWN' => 'funds_withdrawn_at',
        'DISPUTE_FUNDS_REINSTATED' => 'funds_reinstated_at'
      }.freeze

      # @param now [Time] 基准时刻（注入便于测试/复跑）
      # @param limit [Integer] 单次候选上限（同时约束执行期的 provider 只读调用次数）
      # @param verify_after_hours [Numeric] 非终态争议「多久未更新即需再验证」阈值
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(nil, message)
      def call(now: Time.current, limit: DEFAULT_LIMIT, verify_after_hours: DEFAULT_VERIFY_AFTER_HOURS)
        candidates = []
        seen = {}

        grouped_selections(now, limit, verify_after_hours).each do |selection, records|
          records.each do |dispute|
            next if seen[dispute.id]

            seen[dispute.id] = true
            candidates << item_for(dispute, selection, now)
          end
        end

        candidates = candidates.first(limit)
        success(candidates: candidates, observed_at: now, scanned_count: candidates.size,
                limit: limit, verify_after_hours: verify_after_hours)
      end

      private

      def grouped_selections(now, limit, verify_after_hours)
        {
          'attention' => base_scope.where.not(attention_reason: nil).order(:updated_at, :id).limit(limit),
          'journal_gap' => base_scope.where(journal_gap_condition).order(:updated_at, :id).limit(limit),
          'stale_active' => stale_active_scope(now, verify_after_hours, limit)
        }
      end

      def base_scope
        PallasTrade::Dispute.all
      end

      def stale_active_scope(now, verify_after_hours, limit)
        base_scope.where.not(state: PallasTrade::Dispute::TERMINAL_STATES).
          where(updated_at: ..(now - verify_after_hours.to_f.hours)).
          order(:updated_at, :id).
          limit(limit)
      end

      # 「有 funds 时间戳但没有对应账行」的反连接条件（值全部来自代码常量，无注入面）
      def journal_gap_condition
        disputes = PallasTrade::Dispute.table_name
        entries = PallasTrade::FinancialLedgerEntry.table_name

        FUNDS_ATTRIBUTE_BY_ENTRY_TYPE.map do |entry_type, attribute|
          "#{disputes}.#{attribute} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #{entries} " \
            "WHERE #{entries}.dispute_id = #{disputes}.id AND #{entries}.entry_type = '#{entry_type}')"
        end.join(' OR ')
      end

      def item_for(dispute, selection, now)
        {
          dispute: dispute,
          dispute_id: dispute.prefixed_id,
          selection: selection,
          state: dispute.state,
          attention_reason: dispute.attention_reason,
          age_hours: age_hours(dispute, now)
        }
      end

      def age_hours(dispute, now)
        return nil if dispute.updated_at.nil?

        ((now - dispute.updated_at) / 3600.0).round(2)
      end
    end
  end
end
