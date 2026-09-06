# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation)
#
# Refunds::Execute —— durable Refund 的显式执行器（v1 同步）。
# 语义（源文档 REV-P6 §13-20 / REV-INV-03/04/05）：
#   requested → claim(requested→processing, payment 锁内重校验 capacity) → commit
#   → provider I/O（携带稳定 provider_idempotency_key）
#   → outcome apply：succeeded(ApplySuccess) / failed / ambiguous —— 均持久化，不 raise 回滚。
#
# 幂等：仅 requested 可 claim；终态（succeeded/failed/manual_review/canceled）直接返回现状，
#       不产生第二笔 provider refund（REV-INV-04）。
# ApplySuccess 独立可重放：provider 已成功但本地投影失败 → refund 停留在 processing/ambiguous，
#       可再次 ApplySuccess（不重复退款，AC-6006 底座；完整 Recover 服务 = REV-P6-6）。
#
# 兼容边界：legacy 入口（reimbursement / gateway cancel）可能在外层事务内同步调用本服务；
#   v1 中 provider I/O 可能仍位于其外层事务内（该链事务重构 = REV-P6-2/4/5）。
#   raise_on_failure=true 时，结果非 succeeded 会 raise Core::GatewayError（沿用旧调用方语义）。
module PallasTrade
  module Refunds
    class Execute
      prepend PallasTrade::ServiceModule::Base

      # @param refund [PallasTrade::Refund]
      # @param raise_on_failure [Boolean] 默认 false（Admin API 语义：返回终态供展示）；
      #   legacy 路径传 true 以保留"退款失败 = 调用失败"语义。
      # @return [PallasTrade::ServiceModule::Result] value = refund（执行后终态）
      def call(refund:, raise_on_failure: false)
        return failure(nil, 'Refund not found') if refund.nil?

        refund = PallasTrade::Refund.find_by(id: refund.id)
        return failure(nil, 'Refund not found') if refund.nil?

        # 幂等：终态不重复执行
        return success(refund) if refund.state.in?(PallasTrade::Refund::TERMINAL_STATES)

        outcome = claim(refund)
        return apply_outcome(refund, outcome, raise_on_failure:) unless outcome == :claimed

        outcome = execute_provider(refund)
        apply_outcome(refund, outcome, raise_on_failure:)
      end

      private

      # 在 payment 锁内 claim（短事务）：重校验 capacity（排除自身，AC-6008/6009）→
      # requested→processing + 写入 provider_idempotency_key + attempt_count。
      # @return [Symbol] :claimed | :capacity_exceeded | :already_terminal
      def claim(refund)
        payment = refund.payment
        payment.with_lock do
          refund.reload
          return :already_terminal if refund.state.in?(PallasTrade::Refund::TERMINAL_STATES)
          return :claimed if refund.state == 'processing'

          unless refund.state == 'requested'
            # requested 之外的 in-flight/异常态：不推进（ambiguous 等由 REV-P6-6 决策）
            return :already_terminal
          end

          reserved = payment.refunds.capacity_consuming.where.not(id: refund.id).sum(:amount).to_d
          allowed = payment.amount.to_d - payment.offsets_total.abs.to_d - reserved
          if refund.amount.to_d > allowed
            refund.record_failure!(code: 'CAPACITY_EXCEEDED', message: 'Refund amount exceeds the payment credit allowed')
            return :capacity_exceeded
          end

          refund.provider_idempotency_key ||= refund.execution_idempotency_key
          refund.attempt_count = (refund.attempt_count || 0) + 1
          refund.start_processing!
          :claimed
        end
      end

      # Provider I/O（DB lock 外）。结果三态：succeeded / failed（明确拒绝）/ ambiguous（未知/超时）。
      def execute_provider(refund)
        payment = refund.payment
        method = payment.payment_method
        credit_cents = PallasTrade::Money.new(refund.amount.to_f, currency: payment.currency || refund.currency).amount_in_cents

        response = if method.payment_profiles_supported?
                     method.credit(credit_cents, payment.source, payment.transaction_id,
                                   originator: refund, idempotency_key: refund.provider_idempotency_key)
                   else
                     method.credit(credit_cents, payment.transaction_id,
                                   originator: refund, idempotency_key: refund.provider_idempotency_key)
                   end

        if response.success?
          @_gateway_response = response
          :succeeded
        else
          text = response.params['message'] || response.params['response_reason_text'] || response.message
          Rails.logger.error(PallasTrade.t(:gateway_error) + "  Refund #{refund.prefixed_id} rejected: #{text}")
          refund.record_failure!(code: 'PROVIDER_REJECTED', message: text)
          :failed
        end
      rescue PallasTrade::Core::GatewayError => e
        if ambiguous_error?(e)
          Rails.logger.error("[Refunds::Execute] ambiguous outcome refund=#{refund.prefixed_id}: #{e.class} #{e.message}")
          refund.record_ambiguous!(code: 'PROVIDER_AMBIGUOUS', message: e.message)
          :ambiguous
        else
          refund.record_failure!(code: 'PROVIDER_ERROR', message: e.message)
          :failed
        end
      rescue StandardError => e
        Rails.logger.error("[Refunds::Execute] unexpected error refund=#{refund.prefixed_id}: #{e.class} #{e.message}")
        refund.record_ambiguous!(code: 'UNKNOWN_ERROR', message: "#{e.class}: #{e.message}")
        :ambiguous
      end

      # 收敛本地状态（各自独立 DB 写入；ApplySuccess 单事务、幂等可重放）。
      def apply_outcome(refund, outcome, raise_on_failure:)
        case outcome
        when :succeeded
          response = @_gateway_response
          authorization = response.respond_to?(:authorization) ? response.authorization : response&.id
          PallasTrade::Refund.transaction do
            refund.apply_success!(authorization: authorization, response: response)
          end
        when :ambiguous
          # 已在 execute_provider 内持久化 ambiguous（REV-INV-04：不自动重退）
        when :failed, :capacity_exceeded
          # 已在 claim/execute_provider 内持久化 failed
        when :already_terminal
          # 现状即终态
        end

        if raise_on_failure && !refund.succeeded?
          raise PallasTrade::Core::GatewayError, (refund.last_error_message || 'Refund execution failed')
        end

        success(refund)
      end

      # 判定"不知道 provider 是否已退款"（超时/网络类）→ ambiguous；其余视为明确失败。
      # v1 采用保守消息分类；provider 错误码细分属 REV-P6-6/7（不可自动重退 = 安全默认）。
      def ambiguous_error?(error)
        error.message.to_s.match?(/timeout|timed out|\bconnection\b|network|unreachable|ECONN|unable to connect|read error|reset by peer|closed/i)
      end
    end
  end
end
