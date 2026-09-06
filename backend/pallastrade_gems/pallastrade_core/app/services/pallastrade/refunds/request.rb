# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-2 (PRD-20260906-payments-rev-p6-2-refund-execution-orchestration)
#
# Refunds::Request —— 唯一「发起退款」入口（源文档 REV-P6 §12/§16/§57）：
#   capacity 校验 → durable Refund(requested) 落库 → enqueue Refunds::ExecuteJob。
#
# 语义：
#   - durable-first（AC-6001）：本地 durable 行先于任何 PSP 副作用；
#   - 本服务绝不调用 provider / 不把 provider I/O 放进自身事务（REV-INV-03）；
#     资金执行一律由后台 Refunds::ExecuteJob 承担（REV-P6-2）。
#   - ownership 可证明时冻结（payment / reimbursement / target_order / payment_split /
#     commerce_transaction），禁止事后猜填（AC-6029）。
#   - Request 失败（容量/校验）→ failure(refund) 且不 enqueue（AC-6002）。
#
# 兼容：Admin API（controller 内先 authorize+build+save 后再 enqueue）与 gateway cancel/
# reimbursement 均收敛到 durable(requested) → ExecuteJob 的同一 async 语义。
module PallasTrade
  module Refunds
    class Request
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment] 待退款支付
      # @param amount [Numeric, String] 退款金额
      # @param reason [PallasTrade::RefundReason, nil] 必填（Refund validation）；调用方传入
      # @param refunder_id [Integer, nil] 操作人（admin user）
      # @param reimbursement [PallasTrade::Reimbursement, nil] 售后报销上下文（可选）
      # @param commerce_transaction [PallasTrade::CommerceTransaction, nil] ownership（可证明才传）
      # @param target_order [PallasTrade::Order, nil] ownership：组合退款目标子订单（可证明才传）
      # @param payment_split [PallasTrade::PaymentSplit, nil] ownership：组合退款目标 split（可证明才传）
      # @return [PallasTrade::ServiceModule::Result] success(value=refund, requested)
      def call(payment:, amount:, reason: nil, refunder_id: nil, reimbursement: nil,
               commerce_transaction: nil, target_order: nil, payment_split: nil)
        refund = payment.refunds.build(amount: amount, reason: reason, reimbursement: reimbursement)
        refund.refunder_id = refunder_id if refunder_id
        refund.commerce_transaction = commerce_transaction if commerce_transaction
        refund.target_order = target_order if target_order
        refund.payment_split = payment_split if payment_split

        unless refund.save
          return failure(refund)
        end

        enqueue_execution(refund)
        success(refund)
      end

      private

      def enqueue_execution(refund)
        PallasTrade::Refunds::ExecuteJob.perform_later(refund.id)
      end
    end
  end
end
