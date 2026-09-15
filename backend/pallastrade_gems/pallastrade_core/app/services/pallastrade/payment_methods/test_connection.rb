# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 支付配置选项化，切片3）—— 凭证体检（Test connection）。
#
# 语义（业务方案 §63.5/§63.7）：
#   1. 本地体检：该 provider 的 `:password` 型凭证是否齐备（缺失 → missing_credentials，**不猜**值）；
#   2. 远端探测：provider 覆盖 `PaymentMethod#test_connection` 时执行一次只读探测
#      （返回 nil = 无远端能力 → 仅本地体检通过即 ok）；
#   3. 结果归一为 { ok, code, message, checked_at } —— 由调用方（admin）写回
#      `metadata['last_test_connection']`（本服务不落库，保持只读/可重放）。
#
# 安全：message 一律经过凭证值脱敏（值 → [FILTERED]）+ 截断；日志只记 id/code。
module PallasTrade
  module PaymentMethods
    class TestConnection
      prepend PallasTrade::ServiceModule::Base

      OK_CODE = 'ok'
      NO_CREDENTIALS_CODE = 'no_credentials_required'
      CREDENTIALS_PRESENT_CODE = 'credentials_present'
      MISSING_CREDENTIALS_CODE = 'missing_credentials'
      NETWORK_ERROR_CODE = 'network_unreachable'
      PROBE_FAILED_CODE = 'probe_failed'
      PROBE_ERROR_CODE = 'probe_error'

      # 网络类错误按**类名**归一（core 不依赖任何 provider SDK 的异常类）。
      NETWORK_ERROR_PATTERN = /connection|timeout|socket|network|unreachable|econnrefused|dns/i
      MESSAGE_LIMIT = 300

      # @param payment_method [PallasTrade::PaymentMethod]
      # @return [PallasTrade::ServiceModule::Result] value = 体检报告 Hash（string keys）
      def call(payment_method:)
        return failure(nil, 'Payment method is required') if payment_method.blank?

        credential_keys = Array(payment_method.preferences_of_type(:password))
        if credential_keys.empty?
          return success(report(payment_method, true, NO_CREDENTIALS_CODE,
                                'This provider does not require credentials'))
        end

        missing = missing_credential_keys(payment_method, credential_keys)
        if missing.any?
          return success(report(payment_method, false, MISSING_CREDENTIALS_CODE,
                                "Missing credentials: #{missing.join(', ')}"))
        end

        probe = payment_method.test_connection
        if probe.nil?
          return success(report(payment_method, true, CREDENTIALS_PRESENT_CODE,
                                'Credentials are present (this provider has no remote probe)'))
        end

        normalized = normalize_probe(probe)
        success(report(payment_method, normalized[:ok], normalized[:code], normalized[:message]))
      rescue StandardError => e
        success(
          report(
            payment_method,
            false,
            network_error?(e) ? NETWORK_ERROR_CODE : PROBE_ERROR_CODE,
            sanitize(payment_method, e.message).presence || e.class.name
          )
        )
      end

      private

      def missing_credential_keys(payment_method, credential_keys)
        credential_keys.select { |key| payment_method.preferences[key].blank? }.map(&:to_s)
      end

      # provider 返回值归一：Hash{ok:,code:,message:} / true / false / 其他（一律视为未通过）。
      def normalize_probe(probe)
        return { ok: probe == true, code: '', message: '' } unless probe.is_a?(Hash)

        raw_ok = probe.key?(:ok) ? probe[:ok] : probe['ok']
        {
          ok: ActiveModel::Type::Boolean.new.cast(raw_ok) == true,
          code: (probe[:code] || probe['code']).to_s.strip,
          message: (probe[:message] || probe['message']).to_s.strip
        }
      end

      def network_error?(error)
        error.class.name.match?(NETWORK_ERROR_PATTERN)
      end

      # 体检报告：string keys（直接 JSON 落 metadata）。
      def report(payment_method, ok, code, message)
        normalized_code = code.to_s.presence || (ok ? OK_CODE : PROBE_FAILED_CODE)
        result = {
          'ok' => ok,
          'code' => normalized_code,
          'message' => sanitize(payment_method, message).presence,
          'checked_at' => Time.current.iso8601
        }

        Rails.logger.info(
          "[PallasTrade::PaymentMethods::TestConnection] payment_method=#{payment_method&.prefixed_id} " \
          "ok=#{result['ok']} code=#{result['code']}"
        )

        result
      end

      # 凭证值脱敏：任何凭证原文出现在 message 里 → [FILTERED]（防 provider 回显）。
      def sanitize(payment_method, message)
        text = message.to_s.first(MESSAGE_LIMIT * 4)
        Array(payment_method&.preferences_of_type(:password)).each do |key|
          value = payment_method.preferences[key]
          next if value.blank?

          text = text.gsub(value.to_s, '[FILTERED]')
        end
        text.first(MESSAGE_LIMIT)
      end
    end
  end
end
