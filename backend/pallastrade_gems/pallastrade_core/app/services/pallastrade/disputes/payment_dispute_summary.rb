# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-9 (PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics)
#
# Disputes::PaymentDisputeSummary —— **支付级多争议只读聚合**（FR-P79-07）。
#
# 回答运营三个问题：这笔支付被争议了**几笔**、**合计多少钱**、**还剩多少可争议额度**
# （一个 payment 可携带 1:N 争议与部分金额 —— 见 data-model SKILL §Disputes）。
#
# 铁律（源计划 §71 / P7-0 B1–B7）：
#   - **零写**：不创建/更新任何 Dispute / Payment / Ledger / Fact / Order / Inventory 行；
#   - **零 provider I/O**：纯本地读（`Dispute.where(payment_id:)`），不触网；
#   - **零决策**：`exceeds_payment` / `mixed_currency` 只是**提示**，绝不触发资金动作或状态迁移；
#   - **不做算术幻觉**：币种不一致时不给合计（`mixed_currency: true` + `disputed_total: nil`）。
module PallasTrade
  module Disputes
    class PaymentDisputeSummary
      prepend PallasTrade::ServiceModule::Base

      CAPABILITY = 'LOCAL_READ_ONLY'

      # @param payment [PallasTrade::Payment]
      # @param disputes [ActiveRecord::Relation, Array, nil] 预取集合（可选；缺省按 payment 查询）
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(nil, message)
      def call(payment:, disputes: nil)
        return failure(nil, 'Payment required') if payment.nil?

        rows = (disputes || scope_for(payment)).to_a
        payment_amount = payment.respond_to?(:amount) ? payment.amount&.to_d : nil
        payment_currency = payment.respond_to?(:currency) ? payment.currency&.to_s : nil

        currencies = rows.map { |row| row.currency.to_s.upcase }.reject(&:blank?).uniq
        mixed_currency = currencies.size > 1
        disputed_total = mixed_currency ? nil : rows.sum { |row| row.amount.to_d }

        success(
          payment_id: prefixed(payment, 'pay_'),
          currency: mixed_currency ? nil : (currencies.first.presence || payment_currency),
          payment_amount: payment_amount,
          dispute_count: rows.size,
          active_count: rows.count { |row| !row.terminal? },
          disputed_total: disputed_total,
          remaining_amount: remaining_amount(payment_amount, disputed_total, mixed_currency),
          exceeds_payment: exceeds_payment?(payment_amount, disputed_total, mixed_currency),
          mixed_currency: mixed_currency,
          attention_count: rows.count(&:attention?),
          disputes: rows.map { |row| row_summary(row) },
          capability: CAPABILITY,
          observed_at: Time.current
        )
      end

      private

      def scope_for(payment)
        PallasTrade::Dispute.where(payment_id: payment.id).order(:created_at, :id)
      end

      # 剩余额度只在「有支付额 + 有单一币种合计」时才给（否则 nil = 不可判定，不猜）
      def remaining_amount(payment_amount, disputed_total, mixed_currency)
        return nil if mixed_currency || payment_amount.nil? || disputed_total.nil?

        (payment_amount - disputed_total)
      end

      def exceeds_payment?(payment_amount, disputed_total, mixed_currency)
        return false if mixed_currency || payment_amount.nil? || disputed_total.nil?

        disputed_total > payment_amount
      end

      def row_summary(dispute)
        {
          dispute_id: dispute.prefixed_id,
          state: dispute.state,
          kind: dispute.kind,
          amount: dispute.amount&.to_d,
          currency: dispute.currency,
          terminal: dispute.terminal?,
          attention_reason: dispute.attention_reason,
          evidence_due_at: dispute.evidence_due_at
        }
      end

      # Payment 的 prefixed id：`prefixed_id` 已存在则直接用（零假设）
      def prefixed(payment, fallback_prefix)
        return payment.prefixed_id if payment.respond_to?(:prefixed_id) && payment.prefixed_id.present?

        "#{fallback_prefix}#{payment.id}"
      end
    end
  end
end
