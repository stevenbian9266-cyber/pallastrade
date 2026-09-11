# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PRD-20260911-payments-dsp-p7-2 (DSP-P7-2) / 语义冻结：PRD-20260911-payments-dsp-p7-0
    #
    # `DisputeFact` —— dispute 当前**可证明事实**的只读值对象（transient，不落库、无 AR）。
    #
    # 与 `PallasTrade::FinancialFact`（FIN-P4-1）同构：
    #   - `fact_type`   当前最强可证事实（opened / funds withdrawn / funds reinstated / won / lost）
    #   - `status`      该事实的确认度（FIN-INV-09：无法证明 → AMBIGUOUS，绝不猜）
    #   - `resolution`  「provider 状态 ↔ 本地状态」裁决（P7-0 §7；供 P7-6 收敛、P7-5 告警）
    #
    # 构建者：`PallasTrade::Disputes::ResolveFact`（只读）。
    # 消费约束：P7-3 扩展 `FinancialFact::FACT_TYPES` / `FinancialLedgerEntry::ENTRY_TYPES` 时，
    # 必须与本 VO 的 `fact_type` **同名单对齐**（P4 §12 命名纪律）。
    class DisputeFact
      # 事实类型（P7-0 §7 词汇，P7-2 冻结；P7-3 激活到 Journal）
      FACT_TYPES = %w[
        DISPUTE_OPENED DISPUTE_FUNDS_WITHDRAWN DISPUTE_FUNDS_REINSTATED DISPUTE_WON DISPUTE_LOST
      ].freeze

      # 确认度（对齐 FinancialFact::STATUSES 的语义子集；无 AUTHORIZED_ONLY/UNPAID 概念）
      STATUSES = %w[CONFIRMED AMBIGUOUS UNSUPPORTED NOT_APPLICABLE].freeze

      # 裁决（provider ↔ 本地）closed enum —— 只描述判定结果，不触发任何动作
      RESOLUTIONS = %w[
        aligned stale_local stale_provider conflict unknown unsupported unavailable not_applicable
      ].freeze

      # 事实来源（local = 本地 dispute 行 / provider_fetch = 本次只读快照）
      SOURCES = %w[local provider_fetch].freeze

      # 需要人工关注的裁决（P7-5 告警 / P7-6 收敛的输入）
      ATTENTION_RESOLUTIONS = %w[stale_local stale_provider conflict].freeze

      ATTRIBUTES = %i[
        dispute_id payment_id commerce_transaction_id
        fact_type status resolution
        amount currency provider provider_status local_state
        evidence_due_at funds_withdrawn_at funds_reinstated_at
        observed_at source evidence reason_code
      ].freeze

      attr_reader(*ATTRIBUTES)

      # @param attrs [Hash] 仅接受 ATTRIBUTES 白名单键；对象构造后 freeze（不可变）
      def initialize(**attrs)
        unknown = attrs.keys - ATTRIBUTES
        raise ArgumentError, "Unknown DisputeFact attributes: #{unknown.join(', ')}" if unknown.any?

        ATTRIBUTES.each { |a| instance_variable_set("@#{a}", attrs.fetch(a, nil)) }
        freeze
      end

      STATUSES.each { |s| const_set(s, s) }
      FACT_TYPES.each { |t| const_set(t, t) }
      # RESOLUTIONS / SOURCES 为小写枚举值（同 `resolution` 字段字面量），不作常量注册。

      def confirmed?
        status == CONFIRMED
      end

      def ambiguous?
        status == AMBIGUOUS
      end

      def unsupported?
        status == UNSUPPORTED
      end

      def not_applicable?
        status == NOT_APPLICABLE
      end

      def aligned?
        resolution == 'aligned'
      end

      # 需要人工/后续切片处理的裁决（stale/conflict）
      def needs_attention?
        ATTENTION_RESOLUTIONS.include?(resolution)
      end

      # 可入账的资金事实（P7-3 只消费两类；opened/won/lost 是生命周期事实，不产生 Journal）
      def money_movement?
        fact_type.in?(%w[DISPUTE_FUNDS_WITHDRAWN DISPUTE_FUNDS_REINSTATED])
      end
    end
  end
end
