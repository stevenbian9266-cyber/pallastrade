# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8d (PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing)
#
# Refunds::OrphanPairing —— payment ↔ provider 退款引用只读配对（源 REV-P6 §62 边界 + FIN-P4-5）。
#
# 数据面：provider 侧 = `fetch_financial_details(payment_session:)` 归一 hash 的
# `provider_refund_references`（Stripe charge refunds re_[]；Bogus 由本地 refunds 派生）；本地侧 =
# `payment.refunds.where.not(transaction_id: nil)`（transaction_id = apply_success 存的 provider refund id）。
#
# 判定：provider_id ∈ 本地 transaction_id → matched；provider-only → orphans（ORPHAN_REFUND —— provider 有退款
# 而本地无行，如 Stripe 后台/他系统直接退，资金流出不可见）；本地有引用但不在 provider → local_unmatched
# （LOCAL_REFUND_NOT_ON_PROVIDER）。任一 orphan/local_unmatched → needs_attention。
#
# 只读/幂等（同 ReconcilePayment/SourceResult 不变式，P4 §44/AC-4023）：零本地写、零 provider mutation、
# 绝不自动 refund；provider 异常捕获不 raise（unavailable）。能力/锚点判定镜像 ReconcilePayment：
# StoreCredit/Check→not_applicable；无 fetch_financial_details 实现→unsupported；无 session（payment 或组合
# fallback）→unavailable(UNLINKED_LEGACY_PAYMENT)。
module PallasTrade
  module Refunds
    class OrphanPairing
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @return [PallasTrade::ServiceModule::Result] success(OrphanPairingResult) / failure(payment, message)
      def call(payment:)
        return failure(nil, 'Payment not found') if payment.nil?

        pm = payment.payment_method
        return success(not_applicable(payment)) if pm.nil? || pm.is_a?(PallasTrade::PaymentMethod::StoreCredit) ||
                                                   pm.is_a?(PallasTrade::PaymentMethod::Check)
        return success(unsupported(payment)) unless PallasTrade::FinancialFacts::CaptureEvidencePolicy.implements_financial_details?(pm)

        pair(payment, pm)
      end

      private

      def pair(payment, pm)
        session = payment.payment_session
        session ||= payment.payment_combination&.payment_sessions&.first
        if session.nil?
          return success(result(payment, 'unavailable', ['UNLINKED_LEGACY_PAYMENT'],
                               [], [], [], []))
        end

        provider = pm.fetch_financial_details(payment_session: session)
        provider_ids = Array(provider[:provider_refund_references]).compact.map(&:to_s)
        local_refunds = payment.refunds.where.not(transaction_id: nil)
        local_by_ref = local_refunds.each_with_object({}) { |r, h| h[r.transaction_id.to_s] = r }

        matched = []
        orphans = []
        provider_ids.each do |pid|
          if local_by_ref.key?(pid)
            matched << { provider_id: pid, refund_id: local_by_ref[pid].prefixed_id }
          else
            orphans << { provider_id: pid }
          end
        end

        local_unmatched = []
        local_refunds.each do |r|
          local_unmatched << { transaction_id: r.transaction_id, refund_id: r.prefixed_id } unless provider_ids.include?(r.transaction_id.to_s)
        end

        status = (orphans.any? || local_unmatched.any?) ? 'needs_attention' : 'matched'
        reasons = []
        reasons << 'ORPHAN_REFUND' if orphans.any?
        reasons << 'LOCAL_REFUND_NOT_ON_PROVIDER' if local_unmatched.any?

        success(result(payment, status, reasons, provider_ids, matched, orphans, local_unmatched))
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError) => e
        success(result(payment, 'unavailable', ['PROVIDER_UNAVAILABLE', e.message],
                       [], [], [], []))
      end

      def result(payment, status, reasons, provider_ids, matched, orphans, local_unmatched)
        PallasTrade::Refunds::OrphanPairingResult.new(
          status: status,
          reasons: reasons,
          provider_refund_references: provider_ids,
          matched: matched,
          orphans: orphans,
          local_unmatched: local_unmatched,
          observed_at: Time.current
        )
      end

      def not_applicable(payment)
        PallasTrade::Refunds::OrphanPairingResult.new(status: 'not_applicable', reasons: ['NO_PROVIDER_REFUND_CONCEPT'])
      end

      def unsupported(payment)
        PallasTrade::Refunds::OrphanPairingResult.new(status: 'unsupported', reasons: ['PROVIDER_CONTRACT_UNSUPPORTED'])
      end
    end
  end
end
