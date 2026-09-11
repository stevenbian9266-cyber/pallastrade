# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PRD-20260911-payments-dsp-p7-1 (DSP-P7-1)
    #
    # `ProviderPayload` — 把 provider dispute 事件载荷归一为**域内字段**的只读适配器。
    #
    # 现状（P7-1）：只实现 Stripe 形状（`data.object` 下的 dispute 对象，金额为最小货币单位）。
    # 多 provider（Adyen/PayPal 等）按 P7-0 §切片计划留给 **DSP-P7-8**；未知 provider 走
    # `striped?` 之外的通用读取（同形状字段名），解析不到即返回 nil 字段而非猜测。
    #
    # 设计约束：
    #   - 只读：不改任何状态、不发网络请求
    #   - 不猜：缺失字段返回 nil（由调用方决定 attention/状态保持）
    #   - 金额归一：最小货币单位 → decimal（零小数货币不除 100）
    class ProviderPayload
      # Stripe 官方零小数货币（amount 即最小单位本身）——DSP-P7-2 起单一来源在 `PallasTrade::Dispute`
      ZERO_DECIMAL_CURRENCIES = PallasTrade::Dispute::ZERO_DECIMAL_CURRENCIES

      # provider dispute.status → 域内状态（P7-0 §7 映射；未知状态保持原状）
      STATE_BY_PROVIDER_STATUS = {
        'warning_needs_response' => 'needs_response',
        'warning_under_review' => 'under_review',
        'warning_closed' => 'closed',
        'needs_response' => 'needs_response',
        'under_review' => 'under_review',
        'charge_refunded' => 'closed',
        'won' => 'won',
        'lost' => 'lost'
      }.freeze

      attr_reader :provider, :payload

      # @param provider [String] provider 名（payment_method.provider_name / webhook_event.provider）
      # @param payload [String, Hash] provider 事件载荷（JSON 字符串或已解析 Hash）
      def initialize(provider:, payload:)
        @provider = provider.to_s
        @payload = parse(payload)
      end

      def valid?
        object.present? && reference.present?
      end

      def reference
        read(object, :id)&.to_s
      end

      def charge_reference
        stringify_reference(read(object, :charge))
      end

      def payment_reference
        stringify_reference(read(object, :payment_intent))
      end

      def amount
        cents = read(object, :amount)
        return nil if cents.nil?

        normalized_amount(cents, currency)
      end

      def currency
        read(object, :currency)&.to_s
      end

      def provider_status
        read(object, :status)&.to_s
      end

      # provider 原因码（如 fraudulent / product_not_received）
      def reason
        read(object, :reason)&.to_s
      end

      def network_reason_code
        read(object, :network_reason_code)&.to_s
      end

      # 域内状态（未知 provider 状态 → nil，由调用方保持原状态）
      def state
        STATE_BY_PROVIDER_STATUS[provider_status]
      end

      # warning_* 归入 warning，其余为 chargeback
      def kind
        return 'warning' if provider_status.to_s.start_with?('warning')

        'chargeback'
      end

      # 证据提交截止时间（Stripe: evidence_details.due_by，unix 秒）
      def evidence_due_at
        due_by = read(read(object, :evidence_details), :due_by) || read(object, :evidence_due_by)
        return nil if due_by.nil?

        Time.zone.at(due_by.to_i)
      end

      def evidence_submitted_at
        submitted = read(object, :evidence_submitted_at)
        return Time.zone.at(submitted.to_i) if submitted.present?

        details = read(object, :evidence_details)
        return nil if details.nil?

        has_evidence = read(details, :has_evidence)
        return nil unless has_evidence

        # provider 只给"已提交"布尔时用事件时间兜底（Observed，不猜具体时刻）
        Time.zone.at(read(object, :created).to_i)
      end

      def outcome
        case state
        when 'won' then 'won'
        when 'lost' then 'lost'
        when 'closed' then provider_status == 'charge_refunded' ? 'accepted' : nil
        end
      end

      private

      def parse(raw)
        return raw if raw.is_a?(Hash)
        return {} if raw.blank?

        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end

      def object
        @object ||= payload.dig('data', 'object') || payload['object'] || {}
      end

      def read(node, key)
        return nil unless node.respond_to?(:[])

        node[key.to_s] || node[key]
      end

      def stringify_reference(value)
        return nil if value.nil?

        value.is_a?(Hash) ? read(value, :id)&.to_s : value.to_s
      end

      # DSP-P7-2：换算逻辑单一来源（`PallasTrade::Dispute.normalize_provider_amount`）——
      # 零小数货币不除 100；此处保持历史返回类型 Float（ProviderPayload 契约不变）。
      def normalized_amount(value, currency_code)
        PallasTrade::Dispute.normalize_provider_amount(value, currency_code)&.to_f
      end
    end
  end
end
