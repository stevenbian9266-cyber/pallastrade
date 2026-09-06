# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::ResolvePayment —— 把单个 Payment 解析为标准 FinancialFact（FR-4P1-15~21）。
#
# 解析顺序（FR-4P1-17）：
#   1. Classify instrument（InstrumentClassifier）
#   2. Resolve CommerceTransaction ownership（OwnershipResolver，显式 context 优先）
#   3. Resolve amount / currency（来源冲突 → AMBIGUOUS，FR-4P1-18）
#   4. Evaluate capture evidence（CaptureEvidencePolicy，仅 PSP_CASH）
#   5. Produce FinancialFact
#
# 只读边界（FR-4P1-38/39）：本服务不创建/更新/删除任何记录、不调用 capture/refund/credit、
# 不发 provider 网络请求、不创建 Journal。支持 1 CommerceTransaction → N confirmed payment facts
# （FR-4P1-20：禁止“只取第一个 successful Payment”假设）与 short payment 合法表达（FR-4P1-21）。
module PallasTrade
  module FinancialFacts
    class ResolvePayment
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @param transaction [PallasTrade::CommerceTransaction, nil] 显式 ownership context（可选）
      # @return [PallasTrade::ServiceModule::Result]
      #   success(PallasTrade::FinancialFact) —— 业务上“无法证明”通过 fact.status=AMBIGUOUS/UNSUPPORTED 表达，
      #   不是 failure（failure 仅用于输入缺失/不可解析）。
      def call(payment:, transaction: nil)
        return failure(nil, 'Payment not found') if payment.nil?

        ownership = PallasTrade::FinancialFacts::OwnershipResolver.call(
          payment: payment, explicit_transaction: transaction
        )
        return failure(payment, ownership.error) unless ownership.success?

        instrument = PallasTrade::FinancialFacts::InstrumentClassifier.call(payment_method: payment.payment_method)
        return failure(payment, 'Payment method missing') if instrument.failure?

        success(build_fact(payment, ownership.value, instrument.value))
      end

      private

      # ---- Fact builders -------------------------------------------------

      def store_credit_fact(payment, base)
        if payment.completed?
          fact(base, PallasTrade::FinancialFact::STORE_CREDIT_APPLIED, PallasTrade::FinancialFact::CONFIRMED,
               payment.amount, [:store_credit_payment_completed], nil)
        elsif %w[failed void invalid].include?(payment.state)
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::UNPAID,
               nil, [:store_credit_payment_not_applied], "store_credit_#{payment.state}")
        else
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::AMBIGUOUS,
               nil, [:store_credit_incomplete], 'store_credit_not_completed')
        end
      end

      def offline_fact(payment, base)
        if payment.completed?
          fact(base, PallasTrade::FinancialFact::OFFLINE_PAYMENT_RECORDED, PallasTrade::FinancialFact::CONFIRMED,
               payment.amount, [:offline_payment_recorded], nil)
        elsif %w[failed void invalid].include?(payment.state)
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::UNPAID,
               nil, [:offline_payment_not_recorded], "offline_#{payment.state}")
        else
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::AMBIGUOUS,
               nil, [:offline_payment_incomplete], 'offline_payment_not_completed')
        end
      end

      # PSP_CASH：capture evidence policy 是唯一 captured 判定入口（FR-4P1-08/09/10/11/14）。
      # policy 仅在 payment/payment_method 缺失时 failure——call 已保证二者存在，故直接取值。
      def psp_cash_fact(payment, base)
        policy = PallasTrade::FinancialFacts::CaptureEvidencePolicy.call(payment: payment)
        verdict = policy.value[:verdict]
        case verdict
        when :captured
          fact(base, PallasTrade::FinancialFact::CASH_CAPTURED, PallasTrade::FinancialFact::CONFIRMED,
               policy.value[:captured_amount], policy.value[:evidence], nil)
        when :authorized_only
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::AUTHORIZED_ONLY,
               nil, policy.value[:evidence], 'authorized_only')
        when :unpaid
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::UNPAID,
               nil, policy.value[:evidence], "unpaid_#{payment.state}")
        else # :ambiguous —— 证据冲突/缺失：不猜（FR-4P1-14）
          fact(base, PallasTrade::FinancialFact::CASH_CAPTURED, PallasTrade::FinancialFact::AMBIGUOUS,
               nil, policy.value[:evidence], 'capture_evidence_ambiguous')
        end
      end

      def unknown_fact(payment, base)
        # UNKNOWN instrument：不默认 PSP_CASH（FR-4P1-07）→ UNSUPPORTED
        fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::UNSUPPORTED,
             nil, [:unknown_instrument], 'instrument_class_unknown')
      end

      # ---- Shared helpers ------------------------------------------------

      # currency 冲突 → 返回 AMBIGUOUS fact（FR-4P1-18）；统一由 build 层做
      def build_fact(payment, ownership, instrument)
        instrument_class = instrument[:instrument_class]
        currency_status, currency = resolve_currency(payment, ownership[:transaction])
        return ambiguous_currency_fact(payment, ownership, instrument) unless currency_status == :ok

        base = base_attributes(payment, ownership, instrument, instrument_class).merge(currency: currency)
        case instrument_class
        when PallasTrade::FinancialFact::STORE_CREDIT then store_credit_fact(payment, base)
        when PallasTrade::FinancialFact::OFFLINE then offline_fact(payment, base)
        when PallasTrade::FinancialFact::PSP_CASH then psp_cash_fact(payment, base)
        else unknown_fact(payment, base)
        end
      end

      def ambiguous_currency_fact(payment, ownership, instrument)
        base = base_attributes(payment, ownership, instrument, instrument[:instrument_class])
        fact(base.merge(currency: nil), PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::AMBIGUOUS,
             nil, [:currency_unresolved], 'currency_source_conflict_or_missing')
      end

      # @return [[Symbol, String|nil]] [:ok, currency] | [:conflict, nil] | [:missing, nil]
      def resolve_currency(payment, ownership_transaction)
        candidates = [payment.currency.to_s.presence, payment.payment_session&.currency.to_s.presence].compact
        distinct = candidates.uniq
        if distinct.size > 1
          [:conflict, nil]
        elsif distinct.size == 1
          [:ok, distinct.first]
        elsif ownership_transaction&.currency.present?
          [:ok, ownership_transaction.currency.to_s]
        else
          [:missing, nil]
        end
      end

      def base_attributes(payment, ownership, instrument, instrument_class)
        {
          fact_type: nil, status: nil, amount: nil, currency: nil,
          instrument_class: instrument_class,
          commerce_transaction_id: ownership[:transaction]&.prefixed_id,
          order_id: payment.order&.prefixed_id,
          payment_id: payment.prefixed_id,
          refund_id: nil,
          payment_session_id: payment.payment_session&.prefixed_id,
          payment_combination_id: payment.payment_combination&.prefixed_id,
          provider: instrument[:provider],
          provider_payment_reference: provider_payment_reference(payment),
          provider_refund_reference: nil,
          effective_at: effective_at(payment),
          evidence: [], reason_code: nil
        }
      end

      # PSP reference（pi_/cs_…）：payment.response_code（= alias transaction_id）优先，session external_id 兜底。
      def provider_payment_reference(payment)
        payment.response_code.presence || payment.payment_session&.external_id.presence
      end

      def effective_at(payment)
        event = payment.capture_events.order(:created_at).last
        event ? event.created_at : payment.updated_at
      end

      def fact(base, fact_type, status, amount, evidence, reason_code)
        PallasTrade::FinancialFact.new(
          **base.merge(
            fact_type: fact_type,
            status: status,
            amount: amount,
            evidence: Array(evidence),
            reason_code: reason_code
          )
        )
      end
    end
  end
end
