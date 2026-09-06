# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-2 (PRD-20260905-payments-fin-p4-2)
#
# FinancialLedger::Post —— Immutable Journal 幂等 posting 原语。
# 输入 = FIN-P4-1 `PallasTrade::FinancialFact`（唯一合法 posting input contract，FR-4P1-40）。
# 门禁：仅 CONFIRMED + 激活 entry_type + 可解析 commerce_transaction 的 fact 可 post；
# AMBIGUOUS/UNSUPPORTED/NONE/无 txn → failure（FIN-INV-09 不猜；FIN-INV-08 解析失败不产生副作用）。
# 幂等：先按 idempotency_key 查已有 → 命中返回既有；未命中 insert；
# RecordNotUnique 竞态 rescue 后重查返回（PaymentWebhookEvent.create_unique 模式）。
# 只读边界（对既有资金实体）：不创建/更新 Payment/Refund/Transaction，不改任何 state machine。
module PallasTrade
  module FinancialLedger
    class Post
      prepend PallasTrade::ServiceModule::Base

      # @param financial_fact [PallasTrade::FinancialFact]
      # @param idempotency_key [String, nil] 显式覆盖（缺省 fact_posting_key 派生）
      # @param metadata [Hash] 附加元数据（默认 {}）
      # @return [PallasTrade::ServiceModule::Result] success(FinancialLedgerEntry) / failure
      def call(financial_fact:, idempotency_key: nil, metadata: {})
        return failure(nil, 'Financial fact not found') if financial_fact.nil?

        unless self.class.postable?(financial_fact)
          return failure(financial_fact,
                         'Financial fact is not postable: requires CONFIRMED status, an activated entry type and a commerce transaction')
        end

        transaction = PallasTrade::CommerceTransaction.find_by_prefix_id(financial_fact.commerce_transaction_id)
        return failure(financial_fact, 'Commerce transaction not found') if transaction.nil?

        key = idempotency_key.presence || PallasTrade::FinancialLedgerEntry.fact_posting_key(financial_fact)
        existing = PallasTrade::FinancialLedgerEntry.find_by(idempotency_key: key)
        return success(existing) if existing

        begin
          success(create_entry(financial_fact, transaction, key, metadata))
        rescue ActiveRecord::RecordNotUnique
          # 并发竞态兜底：重查返回既有（不重复 posting）
          success(PallasTrade::FinancialLedgerEntry.find_by!(idempotency_key: key))
        end
      end

      # 门禁谓词（FIN-P4-3 编排复用——PostPayment/PostRefund 用它区分 skipped vs 硬失败）：
      # 仅 CONFIRMED + 激活 entry_type + commerce_transaction + amount/currency 的 fact 可 post。
      def self.postable?(fact)
        fact.present? &&
          fact.confirmed? &&
          PallasTrade::FinancialLedgerEntry::ENTRY_TYPES.include?(fact.fact_type) &&
          fact.commerce_transaction_id.present? &&
          fact.amount.present? &&
          fact.currency.present?
      end

      private

      def create_entry(fact, transaction, key, metadata)
        # FIN-P4-4：payment_split 溯源启用（split-aware posting）——ORDER_ALLOCATION 回填 split。
        PallasTrade::FinancialLedgerEntry.create!(
          commerce_transaction: transaction,
          order: resolve(PallasTrade::Order, fact.order_id),
          payment: resolve(PallasTrade::Payment, fact.payment_id),
          refund: resolve(PallasTrade::Refund, fact.refund_id),
          payment_combination: resolve(PallasTrade::PaymentCombination, fact.payment_combination_id),
          payment_split: resolve(PallasTrade::PaymentSplit, fact.payment_split_id),
          entry_type: fact.fact_type,
          amount: fact.amount.to_d,
          currency: fact.currency.to_s,
          idempotency_key: key,
          effective_at: fact.effective_at.presence || Time.current,
          provider: fact.provider,
          provider_reference: fact.provider_payment_reference.presence || fact.provider_refund_reference,
          metadata: metadata || {}
        )
      end

      # prefixed id（py_/re_/or_…）→ 记录；无法解析返回 nil（Ledger 允许 source 缺席，txn 已在门禁保证）
      def resolve(klass, prefixed_id)
        return nil if prefixed_id.blank?

        klass.find_by_prefix_id(prefixed_id)
      rescue StandardError
        nil
      end
    end
  end
end
