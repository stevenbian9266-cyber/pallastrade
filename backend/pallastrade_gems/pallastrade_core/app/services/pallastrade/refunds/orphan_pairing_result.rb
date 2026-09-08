# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8d (PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing)
#
# Refunds::OrphanPairingResult —— provider↔本地 退款配对结果的 transient 只读 VO（不落库，freeze）。
#
# status 语义（镜像 reconcile SourceResult 只读哲学）：
#   matched           全部 provider refund 引用都有本地行，且本地 succeeded 引用都在 provider
#   needs_attention   orphans（provider-only）或 local_unmatched（本地有引用缺 provider）任一存在
#   not_applicable    StoreCredit / Check（无 provider refund 概念）
#   unsupported       该 payment method 无 fetch_financial_details 实现（legacy 契约）
#   unavailable       无 provider session 锚点（UNLINKED_LEGACY_PAYMENT）或 provider 异常（PROVIDER_UNAVAILABLE）
module PallasTrade
  module Refunds
    class OrphanPairingResult
      STATUSES = %w[matched needs_attention not_applicable unsupported unavailable].freeze
      ATTRIBUTES = %i[
        status reasons provider_refund_references matched orphans local_unmatched observed_at
      ].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(status:, reasons: [], provider_refund_references: [], matched: [],
                     orphans: [], local_unmatched: [], observed_at: Time.current)
        raise ArgumentError, "status must be one of #{STATUSES}" unless STATUSES.include?(status.to_s)

        @status = status.to_s
        @reasons = Array(reasons)
        @provider_refund_references = Array(provider_refund_references)
        @matched = Array(matched)
        @orphans = Array(orphans)
        @local_unmatched = Array(local_unmatched)
        @observed_at = observed_at
        freeze
      end

      def needs_attention?
        status == 'needs_attention'
      end

      def to_h
        ATTRIBUTES.index_with { |a| public_send(a) }
      end

      def as_json(*)
        to_h
      end
    end
  end
end
