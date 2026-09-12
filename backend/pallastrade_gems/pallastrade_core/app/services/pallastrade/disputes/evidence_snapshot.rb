# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PRD-20260912-payments-dsp-p7-4 (DSP-P7-4) / 源计划 §41/§42
    #
    # `EvidenceSnapshot` —— 争议证据的**确定性只读投影**（transient，不落库、无 AR）。
    #
    # 铁律（源计划 §42）：不可得即 `not_available` + 封闭 reason，**禁止推导**——
    # 典型错误是把 `shipped_at` 当成「已送达」；本 VO 的 fulfillment 段 `delivered_at` 恒 `not_available`。
    #
    # 分段：order / transaction / payment / refunds / fulfillment / customer_communication /
    #       policy / provider / journal / reconciliation。
    # 每段结构：{ 'availability' => available|not_available, 'reason' => String|nil, 'data' => Hash }
    class EvidenceSnapshot
      SECTIONS = %w[
        order transaction payment refunds fulfillment
        customer_communication policy provider journal reconciliation
      ].freeze

      AVAILABILITIES = %w[available not_available].freeze

      # 不可得的封闭原因（不猜：无值可填时只能如实说明为什么没有）
      REASONS = %w[
        not_requested not_recorded not_supported provider_unavailable unlinked_payment
        order_missing payment_anchor_missing
      ].freeze

      # 缺失证据清单（供 P7-5 告警 / P7-6 收敛输入 / P7-7 展示）
      MISSING_EVIDENCE = %w[
        PROOF_OF_DELIVERY_NOT_AVAILABLE CUSTOMER_COMMUNICATION_NOT_RECORDED
        TRACKING_MISSING SHIPPED_AT_MISSING
        PROVIDER_SNAPSHOT_UNSUPPORTED PROVIDER_SNAPSHOT_UNAVAILABLE
        ORDER_MISSING PAYMENT_ANCHOR_MISSING JOURNAL_MISSING REFUND_OVERLAP_PRESENT
      ].freeze

      ATTRIBUTES = %i[
        dispute_id fact_type fact_status resolution sections missing_evidence
        submission_ready generated_at source
      ].freeze

      attr_reader(*ATTRIBUTES)

      # @param attrs [Hash] 仅接受 ATTRIBUTES 白名单键；构造后 freeze（不可变）
      def initialize(**attrs)
        unknown = attrs.keys - ATTRIBUTES
        raise ArgumentError, "Unknown EvidenceSnapshot attributes: #{unknown.join(', ')}" if unknown.any?

        ATTRIBUTES.each { |a| instance_variable_set("@#{a}", attrs.fetch(a, nil)) }
        freeze
      end

      def section(name)
        sections[name.to_s]
      end

      def available?(name)
        section(name)&.fetch('availability', nil) == 'available'
      end

      # 本切片**永不**提交证据给 provider（源计划 §43/§67：属危险操作，归 P7-8 且需 permission+confirmation+audit）
      def submission_ready?
        false
      end
    end
  end
end
