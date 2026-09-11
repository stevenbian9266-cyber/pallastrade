# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PRD-20260911-payments-dsp-p7-2 (DSP-P7-2)
    #
    # `Disputes::ResolveFact` —— dispute 的**只读事实裁决**（P7-0 §7 / FR-002）：
    # provider 状态（可选只读快照，优先）↔ 本地 Dispute 状态 → `DisputeFact`（事实 + 确认度 + 裁决）。
    #
    # 边界（P7-0 B2/B3/B4/B5，本服务**零写**）：
    #   - 不写 dispute / order / inventory / payment / 财务账本（裁决持久化属 P7-5/P7-6 切片）
    #   - provider 访问仅限只读 `fetch_dispute_details`（无 mutation、无订阅变更、无重扣款）
    #   - 一切 provider 降级以封闭枚举返回（不抛异常、不猜测 —— FIN-INV-09）
    #
    # 裁决矩阵（`resolution`）：
    #   not_applicable 非 PSP 载体（StoreCredit / Check）
    #   aligned        provider 状态与本地状态一致
    #   stale_local    provider 已到终态而本地未达（漏事件 → P7-6 收敛输入）
    #   stale_provider 本地终态而 provider 未达（本地先行处置）
    #   conflict       双方终态但结论不同；本地 `manual_review` 一律归此类
    #   unsupported    无 provider 状态可判且 fetch 命中「无只读契约」
    #   unavailable    无 provider 状态可判且 fetch 报错（网络/API）
    #   unknown        无 provider 状态可判（未请求 fetch 且无历史 provider_status）
    class ResolveFact
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param fetch [Boolean] true = 先取 provider 只读快照（read-only）再裁决
      # @return [PallasTrade::ServiceModule::Result] success(DisputeFact) / failure(nil, message)
      def call(dispute:, fetch: false)
        return failure(nil, 'Dispute required') if dispute.nil?

        snapshot, degraded = fetch ? provider_snapshot(dispute) : [nil, nil]
        success(build_fact(dispute, snapshot, degraded))
      end

      private

      def build_fact(dispute, snapshot, degraded)
        provider_status = snapshot&.dig(:status).presence || local_provider_status(dispute)
        resolution = resolve_verdict(dispute, provider_status, degraded)
        amount = amount_for(dispute, snapshot)

        PallasTrade::Disputes::DisputeFact.new(
          dispute_id: dispute.id,
          payment_id: dispute.payment_id,
          commerce_transaction_id: dispute.commerce_transaction_id,
          fact_type: fact_type_for(dispute),
          status: status_for(resolution, amount, degraded),
          resolution: resolution,
          amount: amount,
          currency: snapshot&.dig(:currency).presence || dispute.currency,
          provider: dispute.provider,
          provider_status: provider_status,
          local_state: dispute.state,
          evidence_due_at: snapshot&.dig(:evidence_due_at) || dispute.evidence_due_at,
          funds_withdrawn_at: dispute.funds_withdrawn_at,
          funds_reinstated_at: dispute.funds_reinstated_at,
          observed_at: Time.current,
          source: snapshot ? 'provider_fetch' : 'local',
          evidence: evidence_for(snapshot, degraded),
          reason_code: reason_code_for(amount, degraded)
        )
      end

      # provider 只读快照（含降级原因）。
      # @return [Array(Hash|nil, String|nil)] [snapshot, degraded_reason]
      def provider_snapshot(dispute)
        payment_method = dispute.payment&.payment_method
        return [nil, 'UNLINKED_PAYMENT'] if payment_method.nil?
        return [nil, 'PROVIDER_CONTRACT_UNSUPPORTED'] unless implements_dispute_details?(payment_method)

        [payment_method.fetch_dispute_details(dispute: dispute), nil]
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError)
        [nil, 'PROVIDER_UNAVAILABLE']
      end

      # capability 与实现存在性一致：fetch_dispute_details 的 method owner 非 base
      # PaymentMethod（base 只 raise NotImplementedError）= 真实现（FIN-P4-5/6 同模式）。
      def implements_dispute_details?(payment_method)
        return false unless payment_method.respond_to?(:fetch_dispute_details)

        payment_method.method(:fetch_dispute_details).owner != PallasTrade::PaymentMethod
      end

      def resolve_verdict(dispute, provider_status, degraded)
        return 'not_applicable' if non_psp_instrument?(dispute)
        return alignment_verdict(dispute, provider_status) if provider_status.present?
        return 'unsupported' if degraded == 'PROVIDER_CONTRACT_UNSUPPORTED'
        return 'unavailable' if degraded == 'PROVIDER_UNAVAILABLE'

        'unknown'
      end

      def alignment_verdict(dispute, provider_status)
        return 'conflict' if dispute.state == 'manual_review'

        expected = PallasTrade::Disputes::ProviderPayload::STATE_BY_PROVIDER_STATUS[provider_status.to_s]
        return 'unknown' if expected.blank?
        return 'aligned' if expected == dispute.state

        expected_terminal = PallasTrade::Dispute::TERMINAL_STATES.include?(expected)
        local_terminal = dispute.terminal?
        return 'stale_local' if expected_terminal && !local_terminal
        return 'stale_provider' if local_terminal && !expected_terminal
        return 'conflict' if expected_terminal && local_terminal

        # 双方均未达终态 → 以阶段序比较（provider 侧更新记为本地落后，反之本地先行）
        expected_rank = PallasTrade::Dispute::STATE_ORDER.fetch(expected, 0)
        local_rank = PallasTrade::Dispute::STATE_ORDER.fetch(dispute.state, 0)
        return 'stale_local' if expected_rank > local_rank
        return 'stale_provider' if expected_rank < local_rank

        'unknown'
      end

      def status_for(resolution, amount, degraded)
        return 'NOT_APPLICABLE' if resolution == 'not_applicable'
        return 'UNSUPPORTED' if degraded == 'PROVIDER_CONTRACT_UNSUPPORTED'
        return 'AMBIGUOUS' if degraded.present?
        return 'AMBIGUOUS' if amount_unprovable?(amount)
        return 'UNSUPPORTED' if resolution == 'unsupported'
        return 'AMBIGUOUS' if %w[unknown unavailable].include?(resolution)

        'CONFIRMED'
      end

      def reason_code_for(amount, degraded)
        return 'PROVIDER_CONTRACT_UNSUPPORTED' if degraded == 'PROVIDER_CONTRACT_UNSUPPORTED'
        return 'PROVIDER_UNAVAILABLE' if degraded == 'PROVIDER_UNAVAILABLE'
        return 'UNLINKED_PAYMENT' if degraded == 'UNLINKED_PAYMENT'
        return 'AMOUNT_UNPROVABLE' if amount_unprovable?(amount)

        nil
      end

      def amount_unprovable?(amount)
        return true if amount.nil?

        amount.to_d <= 0
      end

      def fact_type_for(dispute)
        return 'DISPUTE_WON' if dispute.state == 'won' || dispute.outcome == 'won'
        return 'DISPUTE_LOST' if dispute.state == 'lost' || dispute.outcome == 'lost'
        return 'DISPUTE_FUNDS_REINSTATED' if dispute.funds_reinstated_at.present?
        return 'DISPUTE_FUNDS_WITHDRAWN' if dispute.funds_withdrawn_at.present?

        'DISPUTE_OPENED'
      end

      # provider 快照金额优先（权威），回退本地行金额
      def amount_for(dispute, snapshot)
        value = snapshot&.dig(:amount) || dispute.amount
        value.respond_to?(:to_d) ? value.to_d : value
      end

      def local_provider_status(dispute)
        metadata = dispute.private_metadata
        return nil unless metadata.respond_to?(:[])

        metadata['provider_status'].presence
      end

      # 非 PSP 载体（StoreCredit / Check）天然无 dispute 语义（FIN-P4-5 NOT_APPLICABLE 同模式）
      def non_psp_instrument?(dispute)
        payment_method = dispute.payment&.payment_method
        return false if payment_method.nil?

        payment_method.is_a?(PallasTrade::PaymentMethod::StoreCredit) ||
          payment_method.is_a?(PallasTrade::PaymentMethod::Check)
      end

      def evidence_for(snapshot, degraded)
        items = [:dispute_row]
        items << :provider_fetch if snapshot.present?
        items << degraded.downcase.to_sym if degraded.present?
        items
      end
    end
  end
end
