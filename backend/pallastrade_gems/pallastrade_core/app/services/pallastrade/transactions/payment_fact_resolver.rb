# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-3 (PRD-20260904-payments-txn-p2-3)
#
# Transactions::PaymentFactResolver —— 判定一个 CommerceTransaction 的**真实资金
# 事实**（本地 DB 可能不一致，仍须能确定）。只读、零副作用；不推进任何状态机、
# 不创建记录、不触发 recovery/finalize（消费方为 TXN-P2-4 Recovery / P2-5 Finalize）。
#
# 判定语义（P2 源文档 §19/§27）：
#   paid      —— 已足额收到资金：本地 completed Payment（金额 >= 交易金额）或
#                provider 权威 succeeded/paid。
#   unpaid    —— 无任何入账迹象：无支付 attempt，或全部 attempt 已终态失败 /
#                provider 明确未支付。
#   ambiguous —— 无法确定：进行中 / 待捕获 / 部分入账（short_payment）/
#                provider 不可达 / 本地证据冲突。绝不猜，交 manual_review。
#
# 本地证据优先：completed Payment 是 P0 的权威本地落点（session.completed? 单独
# 不作为 PAID 依据——session completed 但 Payment 缺失时走 provider 确认，这正是
# "本地不一致仍能确定真实资金事实" 的目标场景）。
module PallasTrade
  module Transactions
    class PaymentFactResolver
      prepend PallasTrade::ServiceModule::Base

      CONFIRMABLE_STATUSES = %w[pending processing completed].freeze
      TERMINAL_NEGATIVE_STATUSES = %w[failed canceled expired].freeze
      PROVIDER_TERMINAL_STATUSES = %i[unpaid canceled expired failed].freeze

      # @param transaction [PallasTrade::CommerceTransaction]
      # @param provider_query [Boolean] 允许对 provider 发起只读状态查询
      # @return Result success({ verdict: :paid|:unpaid|:ambiguous,
      #                          reasons: [Symbol], provider_results: [Hash] })
      def call(transaction:, provider_query: true)
        return failure(nil, 'Transaction not found') if transaction.nil?

        sessions = transaction.payment_sessions.includes(:payment, :payment_method).to_a
        return success(verdict(:unpaid, [:no_attempt], [])) if sessions.empty?

        outcome = evaluate(sessions, transaction, provider_query)
        success(verdict(outcome, @reasons, @provider_results))
      end

      private

      def evaluate(sessions, transaction, provider_query)
        @reasons = []
        @provider_results = []
        if full_local_payment?(sessions, transaction)
          @reasons << :payment_completed
          return :paid
        end

        @reasons << :short_payment if short_local_payment?(sessions, transaction)
        return :paid if provider_paid?(sessions, provider_query)
        return :ambiguous if @reasons.include?(:short_payment)

        unsettled = unsettled_attempt?(sessions)
        @reasons << :all_failed unless unsettled || @reasons.any?
        unsettled ? :ambiguous : :unpaid
      end

      def full_local_payment?(sessions, transaction)
        sessions.any? do |session|
          payment = session.payment
          payment.present? && payment.completed? &&
            same_currency?(payment.currency, transaction.currency) &&
            amount_enough?(payment.amount, transaction.amount)
        end
      end

      def short_local_payment?(sessions, transaction)
        sessions.any? do |session|
          payment = session.payment
          payment.present? && payment.completed? &&
            same_currency?(payment.currency, transaction.currency) &&
            !amount_enough?(payment.amount, transaction.amount)
        end
      end

      # provider 只读确认：只针对没有本地 completed Payment、且仍可能入账的 attempt
      def provider_paid?(sessions, provider_query)
        candidates = sessions.select do |session|
          CONFIRMABLE_STATUSES.include?(session.status) && session.external_id.present? && session.payment.nil?
        end
        return false if candidates.empty?

        unless provider_query
          @reasons << :provider_skipped
          return false
        end

        candidates.each do |session|
          fetch_provider_status(session)
        end
        @reasons.include?(:provider_confirmed)
      end

      def fetch_provider_status(session)
        status = session.payment_method.fetch_payment_status(payment_session: session)
        @provider_results << { session_id: session.prefixed_id, status: status[:status] }
        @reasons << if status[:status] == :paid
                      :provider_confirmed
                    elsif PROVIDER_TERMINAL_STATUSES.include?(status[:status])
                      :provider_unpaid
                    else
                      :provider_pending
                    end
      rescue NotImplementedError
        @reasons << :no_provider_contract
      rescue StandardError
        @reasons << :provider_unavailable
      end

      # 是否仍有"未了结"的 attempt：终态失败被本地确认，或 provider 已确认未支付
      def unsettled_attempt?(sessions)
        sessions.any? do |session|
          next false if TERMINAL_NEGATIVE_STATUSES.include?(session.status)
          next false if session.payment.present?

          @provider_results.none? do |result|
            result[:session_id] == session.prefixed_id && PROVIDER_TERMINAL_STATUSES.include?(result[:status])
          end
        end
      end

      def amount_enough?(paid, expected)
        paid.present? && expected.present? && paid.to_d >= expected.to_d
      end

      def same_currency?(left, right)
        left.to_s == right.to_s
      end

      def verdict(state, reasons, provider_results)
        { verdict: state, reasons: reasons.uniq, provider_results: provider_results }
      end
    end
  end
end
