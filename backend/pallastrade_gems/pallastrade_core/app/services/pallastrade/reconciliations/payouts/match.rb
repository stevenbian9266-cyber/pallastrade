# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# `Reconciliations::Payouts::Match` —— 结算台账行 ↔ 本地支付/退款 的匹配（只读本地 + 写台账行状态）。
#
# 匹配锚点（唯一口径，禁止散落判断）：
#   * `charge` 行 → `Payment#response_code` → `PaymentSession#external_id` → 该会话的 payment
#   * `refund` 行 → `Refund#transaction_id`（provider 退款单号）
#   * `fee` / `adjustment` 行 = provider 侧项目 → 直接 `matched`（不参与本地金额对照）
# 金额比较：`(local - line.gross).abs <= 0.01` → `matched`；否则 `amount_mismatch`（记录差值）；找不到 → `unmatched`。
#
# 铁律：**零资金副作用** —— 只写 `pallastrade_payout_lines`/`pallastrade_payouts` + 审计；
# 绝不修改 Payment/Refund/Journal/Order/库存，也不调 provider。
module PallasTrade
  module Reconciliations
    module Payouts
      class Match
        prepend PallasTrade::ServiceModule::Base

        # @param payout [PallasTrade::Payout]
        # @param actor [Object, nil]
        # @return [PallasTrade::ServiceModule::Result] success({ matched:, unmatched:, amount_mismatch:, status: })
        def call(payout:, actor: nil)
          return failure(nil, 'Payout not found') if payout.nil?

          counts = Hash.new(0)

          payout.lines.find_each do |line|
            status, details, local = match_line(line)
            line.payment = local if local.is_a?(PallasTrade::Payment)
            line.refund = local if local.is_a?(PallasTrade::Refund)
            line.mark_match!(status: status, details: details)
            counts[status.to_s] += 1
          end

          payout.recalculate_totals!
          status = payout.refresh_status!
          record_audit(payout, counts, actor)

          success({ matched: counts['matched'], unmatched: counts['unmatched'],
                    amount_mismatch: counts['amount_mismatch'], status: status })
        end

        private

        # @return [Array(String, Hash, Object|nil)] [match_status, details, 本地记录]
        def match_line(line)
          case line.kind
          when 'fee', 'adjustment'
            ['matched', { 'reason' => 'provider_side_item' }, nil]
          when 'refund'
            match_refund(line)
          else
            match_charge(line)
          end
        end

        def match_charge(line)
          payment = find_payment(line.provider_reference)
          if payment.blank?
            return ['unmatched', { 'reason' => 'local_payment_missing', 'reference' => line.provider_reference }, nil]
          end

          compare_amounts(line, payment.amount, payment,
                          { 'payment_id' => payment.id, 'payment_number' => payment.number,
                            'order_number' => payment.order&.number })
        end

        def match_refund(line)
          refund = PallasTrade::Refund.find_by(transaction_id: line.provider_reference)
          if refund.blank?
            return ['unmatched', { 'reason' => 'local_refund_missing', 'reference' => line.provider_reference }, nil]
          end

          compare_amounts(line, refund.amount, refund, { 'refund_id' => refund.id })
        end

        # 金额对照（容差 0.01）；一致 → matched，否则 amount_mismatch（写入差值）。
        def compare_amounts(line, local_amount, local_record, details)
          local = BigDecimal(local_amount.to_s)
          difference = (local - line.gross_amount.to_d).round(2)
          payload = details.merge('local_amount' => local.to_s, 'provider_amount' => line.gross_amount.to_s)

          if difference.abs <= PallasTrade::PayoutLine::AMOUNT_TOLERANCE
            ['matched', payload.merge('difference' => difference.to_s), local_record]
          else
            ['amount_mismatch', payload.merge('difference' => difference.to_s), local_record]
          end
        end

        # provider 引用 → 本地 Payment（response_code → 会话 external_id）
        def find_payment(reference)
          return nil if reference.blank?

          payment = PallasTrade::Payment.find_by(response_code: reference)
          return payment if payment.present?

          session = PallasTrade::PaymentSession.find_by(external_id: reference)
          return nil if session.blank?

          PallasTrade::Payment.where(payment_session_id: session.id).order(:id).first
        end

        def record_audit(payout, counts, actor)
          PallasTrade::Audit.record(
            actor: actor.presence || 'system',
            action: 'payout_matched',
            resource: payout,
            metadata: {
              matched: counts['matched'],
              unmatched: counts['unmatched'],
              amount_mismatch: counts['amount_mismatch'],
              status: payout.status
            }
          )
        end
      end
    end
  end
end
