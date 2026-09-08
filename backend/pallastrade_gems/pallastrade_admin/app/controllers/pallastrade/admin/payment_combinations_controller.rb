# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8g (PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin; G6)
#
# Admin Payment Combinations —— PaymentCombination/split 只读可视化（Orders → Payment Combinations）。
# index：store 作用域组合列表（状态徽章/金额/成员数/已退合计/交易）；
# show：组合头卡 + 逐成员 PaymentSplit（captured/refunded/credit_allowed + 该 split 退款行[8a 徽章]）
#       + 组合 Payment 卡（state/credit_allowed + 其 refunds）+ CommerceTransaction 卡（摘要 + 互链）。
# 不变式：零资金副作用、零 provider mutation、无写动作（组合资金不可在 Admin 手改）；组合取消/退款走
# REV-P6-8f Admin API 与既有 Admin 端点。N+1 由 ar_lazy_preload 承担（框架自动批量预载）。
module PallasTrade
  module Admin
    class PaymentCombinationsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # GET /admin/payment_combinations
      def index
        super
      end

      # GET /admin/payment_combinations/:id —— 隐式渲染（@payment_combination 由 load_resource 依
      # object_name 赋值）；视图内 ar_lazy_preload 自动批量预载 splits/orders/payments/refunds/txn。

      private

      def model_class
        PallasTrade::PaymentCombination
      end

      def object_name
        'payment_combination'
      end

      def collection_includes
        [:payment_splits, :payments]
      end

      def collection_default_sort
        'created_at desc'
      end
    end
  end
end
