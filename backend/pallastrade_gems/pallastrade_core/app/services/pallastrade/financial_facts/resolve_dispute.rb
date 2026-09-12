# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-3 (PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile)
#
# FinancialFacts::ResolveDispute —— 把单个 Dispute 解析为标准 `FinancialFact`（FR-P73-05）。
#
# 定位（P4 §16 契约纪律）：Journal 只消费 `FinancialFact`，因此争议域经本服务映射，
# 复用 `Disputes::ResolveFact`（P7-2 只读裁决层）作为**唯一**事实来源，不复制任何
# provider 判定逻辑（FIN-P4-1 FR-4P1-40）。
#
# 映射规则（FR-P73-02/05/08）：
#   - 现金事实（`DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED`）→ instrument_class
#     取支付工具分类（StoreCredit/Check → 非 PSP 现金同 Payment 侧口径）；
#     `DISPUTE_FUNDS_WITHDRAWN` 金额取**负数**（资金流出），`REINSTATED` 取正数（资金流入）。
#   - 非现金事实（`DISPUTE_OPENED` / `DISPUTE_WON` / `DISPUTE_LOST`）→ instrument_class UNKNOWN；
#     永不进入 Journal（`ENTRY_TYPES` 不含 → Post 门禁 skip，FR-P73-02）。
#   - `effective_at` 严格取 `funds_withdrawn_at` / `funds_reinstated_at`（**无 fallback**：
#     以 `observed_at`/`Time.current` 兜底会让幂等键随重试漂移 → 重复 posting，FR-P73-07）。
#   - 状态/裁决/证据原样透传（CONFIRMED / AMBIGUOUS / UNSUPPORTED / NOT_APPLICABLE；FIN-INV-09 不猜）。
#
# 只读边界：零写、零 provider I/O（`fetch:` 显式传 true 时才由 P7-2 只读快照路径取数）。
module PallasTrade
  module FinancialFacts
    class ResolveDispute
      prepend PallasTrade::ServiceModule::Base

      # 现金事实（真实资金移动）——只有这两类进入 Journal
      CASH_FACT_TYPES = %w[DISPUTE_FUNDS_WITHDRAWN DISPUTE_FUNDS_REINSTATED].freeze
      # 流出方向的事实（记账金额取负）
      OUTFLOW_FACT_TYPES = %w[DISPUTE_FUNDS_WITHDRAWN].freeze

      # @param dispute [PallasTrade::Dispute]
      # @param fetch [Boolean] true = 先取 provider 只读快照再裁决（默认 false：纯本地、零网络）
      # @param fact_type [String, nil] **事件作用域事实类型提示**（如 `dispute.funds_reinstated` 事件 →
      #   `DISPUTE_FUNDS_REINSTATED`）。
      #   P7-2 的 `fact_type_for` 以**终态优先**（won/lost 覆盖 funds 时间戳），因此一个已 `won` 的争议
      #   携带 `funds_reinstated_at` 时「当前最强事实」= `DISPUTE_WON` —— 若放任入账层沿用该事实，
      #   **返还资金将永不入账**（资金缺口）。入账层因此按**实际发生的现金事件**解析；
      #   不传 hint 时保持 P7-2 语义（供对账/证据读取使用）。
      # @return [PallasTrade::ServiceModule::Result] success(FinancialFact) / failure(dispute, message)
      def call(dispute:, fetch: false, fact_type: nil)
        return failure(nil, 'Dispute not found') if dispute.nil?

        resolution = PallasTrade::Disputes::ResolveFact.call(dispute: dispute, fetch: fetch)
        return failure(dispute, resolution.error) unless resolution.success?

        success(build_fact(dispute, resolution.value, fact_type))
      end

      def self.cash_fact_type?(fact_type)
        CASH_FACT_TYPES.include?(fact_type.to_s)
      end

      private

      def build_fact(dispute, dispute_fact, fact_type)
        type = fact_type.presence || dispute_fact.fact_type
        cash = self.class.cash_fact_type?(type)

        PallasTrade::FinancialFact.new(
          fact_type: type,
          status: dispute_fact.status,
          amount: amount_for(dispute_fact, cash, type),
          currency: dispute_fact.currency,
          instrument_class: instrument_class_for(dispute, cash),
          commerce_transaction_id: dispute.commerce_transaction&.prefixed_id,
          order_id: dispute.order&.prefixed_id,
          payment_id: dispute.payment&.prefixed_id,
          dispute_id: dispute.prefixed_id,
          provider: dispute.provider,
          provider_payment_reference: dispute.provider_payment_reference.presence ||
                                      dispute.provider_charge_reference.presence,
          provider_dispute_reference: dispute.provider_dispute_reference,
          effective_at: effective_at_for(dispute, type),
          evidence: Array(dispute_fact.evidence),
          reason_code: dispute_fact.reason_code
        )
      end

      # 现金事实才带方向符号；非现金事实保留原值（仅作事实描述，不入账）
      def amount_for(dispute_fact, cash, fact_type)
        return dispute_fact.amount if dispute_fact.amount.nil? || !cash

        amount = dispute_fact.amount.to_d
        OUTFLOW_FACT_TYPES.include?(fact_type) ? -amount : amount
      end

      def instrument_class_for(dispute, cash)
        return PallasTrade::FinancialFact::UNKNOWN unless cash

        payment = dispute.payment
        return PallasTrade::FinancialFact::UNKNOWN if payment.nil? || payment.payment_method.nil?

        PallasTrade::FinancialFacts::InstrumentClassifier.call(
          payment_method: payment.payment_method
        ).value[:instrument_class]
      end

      # 记账生效时间 = 资金事实发生时间（**无 fallback**，保证幂等键稳定）
      def effective_at_for(dispute, fact_type)
        case fact_type
        when 'DISPUTE_FUNDS_WITHDRAWN' then dispute.funds_withdrawn_at
        when 'DISPUTE_FUNDS_REINSTATED' then dispute.funds_reinstated_at
        else dispute.resolved_at || dispute.created_at
        end
      end
    end
  end
end
