# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-2 (PRD-20260905-payments-fin-p4-2)
#
# FinancialLedger::Reverse —— 冲销原语（append-only correction，FIN-INV-07/P4 §8）。
# 错误金融事实不原地修改：生成一条 amount 相反、reversal_of 指向原 entry 的新 entry，
# 并把原 entry 标记 reversed（mark_reversed!，唯一白名单原地变化）。
# 重复保护：已 reversed 的 entry 不能再冲销；同一原 entry 至多一条有效(posted) reversal
# （业务层 with_lock + reversals.active 检查 + DB partial UNIQUE 兜底，FIN-INV-09）。
# reversal entry 本身 state=posted，可被再次 reverse（恢复语义）——Ledger 天然支持。
module PallasTrade
  module FinancialLedger
    class Reverse
      prepend PallasTrade::ServiceModule::Base

      # @param entry [PallasTrade::FinancialLedgerEntry]
      # @return [PallasTrade::ServiceModule::Result] success(reversal_entry) / failure
      def call(entry:)
        return failure(nil, 'Ledger entry not found') if entry.nil?

        entry.with_lock do
          current = entry.reload
          return failure(current, 'Entry already reversed') if current.reversed?
          if current.reversals.active.exists?
            return failure(current, 'Entry already has an active reversal')
          end

          reversal = PallasTrade::FinancialLedgerEntry.create!(
            commerce_transaction: current.commerce_transaction,
            order: current.order,
            payment: current.payment,
            refund: current.refund,
            payment_combination: current.payment_combination,
            payment_split: current.payment_split,
            entry_type: current.entry_type,
            amount: -current.amount.to_d,
            currency: current.currency,
            idempotency_key: "reversal:#{current.idempotency_key}",
            reversal_of: current,
            effective_at: Time.current,
            metadata: { reversal: true }
          )
          current.mark_reversed!
          success(reversal)
        end
      end
    end
  end
end
