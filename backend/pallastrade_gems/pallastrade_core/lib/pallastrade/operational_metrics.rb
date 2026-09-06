# frozen_string_literal: true

# CORE-P5-8（2026-09-06）：运营观测埋点 —— 结构化 JSON 计数行唯一入口。
#
# 背景：CORE-P5-0 审计（docs/research/RESEARCH-20260906-p5-0-commerce-core-convergence-audit.md
# §5.7/§10）发现 legacy 完成/回调路径无 runtime 使用计数，无法支撑 CORE-P5-5 Retirement Gate
# （CORE-INV-09：grep=0 ≠ 生产无人使用）。
#
# 约定：
#   - 输出与 P4 sweeper（recover_sweeper/reconcile_sweeper）一致的 { event:, at:, ... }.to_json
#   - key：legacy 使用计数 → event: 'legacy.<metric>.calls'（对齐 P5 §28 legacy_*_calls_total）
#   - 字段只含 prefixed_id / provider / state / entry_point，无 PII/密钥
#   - 纯旁路：logger 异常内部吞掉，绝不 raise、绝不阻断主流程（REQ AC-011）
#   - 不落库、零外部 metrics 依赖（仓库无 Prometheus/statsd，见 REQ Step0 结论）
module PallasTrade
  module OperationalMetrics
    module_function

    # 输出一行 JSON 计数（与 recover_sweeper/reconcile_sweeper 风格一致）。
    # @param event [String] 固定事件名，如 'legacy.checkout_complete.calls'
    # @param fields [Hash] 附加字段（prefixed_id / provider / entry_point …）
    def count(event, **fields)
      Rails.logger.info({ event: event, at: Time.current.iso8601 }.merge(fields).to_json)
    rescue StandardError
      nil # 观测旁路绝不影响主流程（AC-011）
    end

    # legacy 使用计数便捷方法 → event: "legacy.<metric>.calls"
    def legacy(metric, **fields)
      count("legacy.#{metric}.calls", **fields)
    end
  end
end
