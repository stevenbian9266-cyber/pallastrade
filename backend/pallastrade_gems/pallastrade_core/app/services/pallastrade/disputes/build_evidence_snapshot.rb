# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-4 (PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot)
#
# Disputes::BuildEvidenceSnapshot —— 把既有事实投影为一张**可审阅的证据卡**（源计划 §41/§42）。
#
# 只读边界：零写（不落库、不改状态、不创建表）；默认**零 provider 网络 I/O**
#   （仅 `fetch: true` 且 `fetch_dispute_details` capability 存在时取只读快照）。
# 不伪造（源计划 §42）：交付证明/客户沟通等系统无可靠来源的事实一律 `not_available` + 封闭 reason；
#   **禁止**由 `shipped_at` 推导 `delivered_at`。
# 不提交：`submission_ready` 恒 false（源计划 §43/§67：Submit Evidence 属危险操作，归 P7-8）。
# 日志纪律：本服务不写日志、错误仅含 ids/段名（PII 只出现在返回的 VO 内）。
module PallasTrade
  module Disputes
    class BuildEvidenceSnapshot
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param fetch [Boolean] true = 额外取 provider 只读快照（默认 false：纯本地、零网络）
      # @return [PallasTrade::ServiceModule::Result] success(EvidenceSnapshot) / failure(dispute, message)
      def call(dispute:, fetch: false)
        return failure(nil, 'Dispute not found') if dispute.nil?

        resolution = PallasTrade::Disputes::ResolveFact.call(dispute: dispute)
        return failure(dispute, resolution.error) unless resolution.success?

        fact = resolution.value
        sections = build_sections(dispute, fetch)

        success(
          PallasTrade::Disputes::EvidenceSnapshot.new(
            dispute_id: dispute.prefixed_id,
            fact_type: fact.fact_type,
            fact_status: fact.status,
            resolution: fact.resolution,
            sections: sections,
            missing_evidence: missing_evidence(dispute, sections),
            submission_ready: false,
            generated_at: Time.current,
            source: fetch ? 'local+provider_fetch' : 'local'
          )
        )
      end

      private

      def build_sections(dispute, fetch)
        {
          'order' => order_section(dispute),
          'transaction' => transaction_section(dispute),
          'payment' => payment_section(dispute),
          'refunds' => refunds_section(dispute),
          'fulfillment' => fulfillment_section(dispute),
          # 系统没有结构化的客户沟通记录 → 恒不可得（不臆造，源计划 §42）
          'customer_communication' => unavailable('not_recorded'),
          'policy' => policy_section(dispute),
          'provider' => provider_section(dispute, fetch),
          'journal' => journal_section(dispute),
          'reconciliation' => reconciliation_section(dispute)
        }
      end

      # ---- 各段 ----------------------------------------------------------

      def order_section(dispute)
        order = dispute.order
        return unavailable('order_missing') if order.nil?

        available(
          'number' => order.try(:number),
          'email' => order.try(:email),
          'currency' => order.try(:currency),
          'total' => order.try(:total)&.to_d,
          'completed_at' => order.try(:completed_at),
          'billing_address' => address_summary(order.try(:bill_address)),
          'shipping_address' => address_summary(order.try(:ship_address))
        )
      end

      def address_summary(address)
        return nil if address.nil?

        {
          'name' => [address.try(:firstname), address.try(:lastname)].compact.join(' ').presence,
          'address1' => address.try(:address1),
          'city' => address.try(:city),
          'zipcode' => address.try(:zipcode),
          'country' => address.try(:country)&.iso,
          'state' => address.try(:state_name).presence || address.try(:state)&.name
        }
      end

      def transaction_section(dispute)
        transaction = dispute.commerce_transaction
        return unavailable('payment_anchor_missing') if transaction.nil?

        available(
          'id' => transaction.prefixed_id,
          'amount' => transaction.try(:amount)&.to_d,
          'currency' => transaction.try(:currency),
          'state' => transaction.try(:state),
          'created_at' => transaction.try(:created_at)
        )
      end

      def payment_section(dispute)
        payment = dispute.payment
        return unavailable('payment_anchor_missing') if payment.nil?

        available(
          'id' => payment.prefixed_id,
          'provider_payment_reference' => payment.try(:response_code),
          'provider_charge_reference' => dispute.provider_charge_reference,
          'amount' => payment.try(:amount)&.to_d,
          'currency' => payment.try(:currency),
          'state' => payment.try(:state)
        )
      end

      def refunds_section(dispute)
        payment = dispute.payment
        return unavailable('payment_anchor_missing') if payment.nil?

        refunds = PallasTrade::Refund.where(payment_id: payment.id).order(:id).to_a
        total = refunds.sum { |r| r.amount.to_d }

        available(
          'items' => refunds.map { |r| refund_summary(r) },
          'total' => total,
          # 事实层重叠标记（是否存在与该笔支付相关的退款）——不判断法律后果
          'overlap' => refunds.any?
        )
      end

      def refund_summary(refund)
        {
          'id' => refund.prefixed_id,
          'amount' => refund.amount&.to_d,
          'state' => refund.try(:state),
          'provider_reference' => refund.try(:transaction_id),
          'created_at' => refund.try(:created_at)
        }
      end

      def fulfillment_section(dispute)
        order = dispute.order
        return unavailable('order_missing') if order.nil?

        shipments = Array(order.try(:shipments)).map { |s| shipment_summary(s) }

        available(
          'shipments' => shipments,
          # 源计划 §42：系统无可靠的 delivered_at / proof_of_delivery → 恒 not_available，禁止推导
          'delivered_at' => { 'availability' => 'not_available', 'reason' => 'not_recorded', 'value' => nil },
          'proof_of_delivery' => { 'availability' => 'not_available', 'reason' => 'not_recorded', 'value' => nil }
        )
      end

      def shipment_summary(shipment)
        {
          'number' => shipment.try(:number),
          'state' => shipment.try(:state),
          'tracking' => shipment.try(:tracking),
          'shipped_at' => shipment.try(:shipped_at),
          'fulfilled_at' => shipment.try(:updated_at)
        }
      end

      def policy_section(dispute)
        store = dispute.store || dispute.order&.store
        # 系统没有结构化的政策文档模型 → 如实标注不可得，仅附店铺链接供人工参考
        unavailable('not_recorded', 'store_url' => store.try(:url))
      end

      def provider_section(dispute, fetch)
        payment_method = dispute.payment&.payment_method
        return unavailable('unlinked_payment') if payment_method.nil?
        return unavailable('not_requested') unless fetch
        return unavailable('not_supported') unless provider_capability?(payment_method)

        snapshot = payment_method.fetch_dispute_details(dispute: dispute)
        available(snapshot.slice(:provider_dispute_reference, :status, :amount, :currency, :reason,
                                 :network_reason_code, :evidence_due_at, :evidence_submitted_at, :has_evidence))
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError)
        unavailable('provider_unavailable')
      end

      def journal_section(dispute)
        entries = PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).order(:id).to_a
        return unavailable('not_recorded') if entries.empty?

        available('entries' => entries.map { |e| journal_entry_summary(e) },
                  'total' => entries.sum { |e| e.amount.to_d })
      end

      def journal_entry_summary(entry)
        {
          'id' => entry.prefixed_id,
          'entry_type' => entry.entry_type,
          'amount' => entry.amount.to_d,
          'state' => entry.state,
          'provider_reference' => entry.provider_reference,
          'effective_at' => entry.effective_at
        }
      end

      def reconciliation_section(dispute)
        result = PallasTrade::Reconciliations::ReconcileDispute.call(dispute: dispute)
        return unavailable('not_recorded') unless result.success?

        value = result.value
        available('classification' => value[:classification], 'reasons' => value[:reasons],
                  'expected_entries' => value[:expected_entries])
      end

      # ---- 缺失证据清单 ---------------------------------------------------

      def missing_evidence(dispute, sections)
        missing = ['PROOF_OF_DELIVERY_NOT_AVAILABLE', 'CUSTOMER_COMMUNICATION_NOT_RECORDED']
        shipments = sections['fulfillment']['data']['shipments'] || []

        missing << 'TRACKING_MISSING' unless shipments.any? { |s| s['tracking'].present? }
        missing << 'SHIPPED_AT_MISSING' unless shipments.any? { |s| s['shipped_at'].present? }
        missing << 'ORDER_MISSING' unless sections['order']['availability'] == 'available'
        missing << 'PAYMENT_ANCHOR_MISSING' unless sections['payment']['availability'] == 'available'
        missing << 'REFUND_OVERLAP_PRESENT' if sections['refunds']['data']['overlap']
        missing << 'JOURNAL_MISSING' if sections['reconciliation']['data']['classification'] == 'journal_missing'
        missing.concat(provider_gaps(dispute, sections))
        missing
      end

      # capability 检测是**本地事实**（method owner 检查，零 I/O）→ 与 fetch 无关，始终如实报告缺口
      def provider_gaps(dispute, sections)
        payment_method = dispute.payment&.payment_method
        return [] if payment_method.nil?

        gaps = []
        gaps << 'PROVIDER_SNAPSHOT_UNSUPPORTED' unless provider_capability?(payment_method)
        gaps << 'PROVIDER_SNAPSHOT_UNAVAILABLE' if sections['provider']['reason'] == 'provider_unavailable'
        gaps
      end

      # capability = **类级**事实（网关子类是否重写契约）：
      # 用 `class.instance_method` 而非 `obj.method` —— 后者会被 RSpec 打桩（singleton）干扰，
      # 把 stub 误当成「已实现契约」。零 I/O。
      def provider_capability?(payment_method)
        payment_method.class.instance_method(:fetch_dispute_details).owner != PallasTrade::PaymentMethod
      rescue NameError
        false
      end

      # ---- 段构造助手 -----------------------------------------------------

      def available(data)
        { 'availability' => 'available', 'reason' => nil, 'data' => data }
      end

      def unavailable(reason, data = {})
        { 'availability' => 'not_available', 'reason' => reason, 'data' => data }
      end
    end
  end
end
