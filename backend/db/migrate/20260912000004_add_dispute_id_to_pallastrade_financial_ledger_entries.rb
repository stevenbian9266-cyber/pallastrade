# frozen_string_literal: true

# PRD-20260912-payments-dsp-p7-3 (DSP-P7-3)
#
# `pallastrade_financial_ledger_entries` 增加 `dispute_id`：争议资金事实可**直连** dispute 主体。
#
# 为什么必须加列（不是可选优化）：
#   1. 可追溯（P4 §12 命名纪律）：entry 与资金事实同源——payment/refund/allocation 分别有
#      payment_id/refund_id/payment_split_id，争议资金行同理需要 dispute_id 才能审计回溯；
#   2. 幂等键正确性：`FinancialLedgerEntry.fact_posting_key` 原优先级为
#      `refund > payment > combination > split > order > txn`，而**一个 payment 可携带 1:N disputes**
#      （见 `ai/skills/pallastrade-data-model/SKILL.md` §Disputes）→ 同秒同额的两笔争议会派生出
#      相同 key，导致第二笔被**错误去重**（静默丢账）。加列后 key 以 dispute 为最高优先级来源。
#
# 追加式变更：nullable + 索引，无数据回填（P4 §44 口径），历史行不受影响。
class AddDisputeIdToPallasTradeFinancialLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_financial_ledger_entries, :dispute_id, :bigint
    add_index :pallastrade_financial_ledger_entries, :dispute_id
  end
end
