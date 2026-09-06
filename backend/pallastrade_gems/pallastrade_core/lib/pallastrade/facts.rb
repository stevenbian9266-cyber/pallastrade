# frozen_string_literal: true

# CORE-P5-3（2026-09-07）：Fact Resolver 统一 Result contract（P5 §12-13）。
#
# 目标：统一各 Fact Resolver 的“接口风格”（Result contract / evidence 处理 /
# ambiguity 语义 / trace），**不是合并成一个大 Resolver**，也不改变任何判定语义。
#
# 统一概念（P5 §12）：
#   Result 字段：status / reason_code / evidence / observed_at / source
#   status（判定确定性，Symbol）：
#     :confirmed / :unconfirmed / :ambiguous / :unsupported / :not_applicable
# 各领域保留自己的业务 fact：
#   payment    : paid / unpaid（+ ambiguous）
#   inventory  : reserved / committed / released / expired / unreserved /
#                not_required（+ ambiguous）
#   financial  : FinancialFact 值对象大写枚举（financial_fact.rb:21-26）
#
# 本模块提供：确定性词汇 + 领域 verdict → certainty 映射 + 规范字段构造器。
# Resolver 以“超集”方式把规范字段并入既有结果（旧消费方键保持兼容），使日志/
# 采集端可用统一 status/evidence 做跨 resolver 聚合（与 OperationalMetrics 及
# Reconciliation 输出配合）。核心原则对齐 P5 §13：Evidence First / No Guess /
# Read Before Side Effect / Ambiguous → Safe Stop。
module PallasTrade
  module Facts
    module_function

    CONFIRMED = :confirmed
    UNCONFIRMED = :unconfirmed
    AMBIGUOUS = :ambiguous
    UNSUPPORTED = :unsupported
    NOT_APPLICABLE = :not_applicable

    # 领域业务 verdict → 判定确定性（未知值保守回落 :unconfirmed，绝不猜测）
    def certainty_for(domain, verdict)
      case domain
      when :payment then payment_certainty.fetch(verdict, UNCONFIRMED)
      when :inventory then inventory_certainty.fetch(verdict, UNCONFIRMED)
      else UNCONFIRMED
      end
    end

    def payment_certainty
      { paid: CONFIRMED, unpaid: UNCONFIRMED, ambiguous: AMBIGUOUS }.freeze
    end

    def inventory_certainty
      {
        committed: CONFIRMED,
        reserved: CONFIRMED,
        released: CONFIRMED,
        expired: CONFIRMED,
        unreserved: NOT_APPLICABLE,
        not_required: NOT_APPLICABLE,
        ambiguous: AMBIGUOUS
      }.freeze
    end

    # 构造规范 Result 字段（空值压缩；observed_at 缺省取当前时间 ISO8601）。
    # reason_codes/evidence 同源于 Resolver 的 reasons（reasons 保留业务 Symbol）。
    def contract_fields(status:, reason_codes: [], observed_at: nil, source: nil)
      codes = Array(reason_codes).map(&:to_s)
      {
        status: status,
        reason_code: codes.join(','),
        evidence: codes,
        observed_at: observed_at || Time.current.iso8601,
        source: source
      }.compact
    end
  end
end
