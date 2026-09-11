# frozen_string_literal: true

# PRD-20260911-payments-dsp-p7-2 (DSP-P7-2)
#
# `pallastrade_disputes` 补 funds 时间戳：P7-1 只落事件动作（PaymentWebhookEvent.action），
# dispute 行没有「何时扣回资金 / 何时返还」的事实，P7-3 的 Journal/对账缺输入。
#
#   - funds_withdrawn_at  ：provider 扣回资金的观测时点（charge.dispute.funds_withdrawn）
#   - funds_reinstated_at ：provider 返还资金的观测时点（charge.dispute.funds_reinstated）
#
# 写入方 = `PallasTrade::Disputes::HandleProviderEvent`（首次观测写入，不覆盖既有值 → 重复投递幂等）。
# 截止日扫描/告警（含本两列的使用）属 DSP-P7-5；裁决（只读）属 DSP-P7-2 `Disputes::ResolveFact`。
class AddFundsTimestampsToPallasTradeDisputes < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_disputes, :funds_withdrawn_at, :datetime
    add_column :pallastrade_disputes, :funds_reinstated_at, :datetime
  end
end
