# frozen_string_literal: true

# CORE-P5-8（2026-09-06）：CommerceTransaction 关键事件级计数。
#
# 订阅状态机已发布的事件（commerce_transaction.recovery_required / .manual_review，
# commerce_transaction.rb handle_recovery_required/mark_manual_review 已 publish_event，
# 零模型改动），与 RecoverSweeper 的周期 gauge（transactions.recover_sweeper JSON）互补为
# 事件率口径。async: false —— 计数廉价、事件低频，避免 ActiveJob 队列噪声；纯旁路，
# subscriber 异常由事件总线承载，不影响发布方主流程。
module PallasTrade
  class OperationalMetricsSubscriber < PallasTrade::Subscriber
    subscribes_to 'commerce_transaction.recovery_required',
                  'commerce_transaction.manual_review',
                  async: false

    on 'commerce_transaction.recovery_required', :count_event
    on 'commerce_transaction.manual_review', :count_event

    private

    def count_event(event)
      PallasTrade::OperationalMetrics.count(
        event.name,
        transaction_id: event.payload.try(:[], 'id') || event.payload.try(:[], :id)
      )
    end
  end
end
