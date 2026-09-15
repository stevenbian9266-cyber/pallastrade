# frozen_string_literal: true

# PALLAS-CUSTOM: D9（PRD-20260915-payments-d9-支付凭据与环境 切片1）
#
# Provider 凭据到期巡检（业务方案 §68.2）—— **30 / 7 / 1 天**阈值告警：
#   - 遍历 provider 的 `:password` 型偏好 → `PaymentMethod#credentials_status`
#   - `alert_level` ∈ 30d / 7d / 1d / expired 且与**上次已告警级别不同** → 写
#     `private_metadata['credential_alerts'][key] = { level, alerted_at }` + AuditLog
#   - **零 provider 网络调用、零资金副作用**；重复调度幂等（同级别不重复告警；
#     升级（30d→7d→1d→expired）与重新轮换后再次到期都会重新告警）
module PallasTrade
  module PaymentMethods
    class CredentialExpiryCheckJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      ALERT_LEVELS = %w[30d 7d 1d expired].freeze

      # @param store_id [Integer, nil] 限定单店（默认全店）
      # @param now [String, Time, nil] 注入当前时间（测试用）
      # @return [Integer] 本次新增告警数
      def perform(store_id: nil, now: nil)
        current_time = now.present? ? Time.zone.parse(now.to_s) : Time.current
        providers = scope(store_id).to_a
        alerted = 0

        providers.each do |payment_method|
          payment_method.credentials_status(now: current_time).each do |status|
            next unless ALERT_LEVELS.include?(status['alert_level'])
            next unless alert?(payment_method, status)

            persist_alert(payment_method, status, current_time)
            alerted += 1
          end
        end

        Rails.logger.info(
          "[credential-expiry] providers=#{providers.size} alerted=#{alerted} at=#{current_time.utc.iso8601}"
        )
        alerted
      end

      private

      def scope(store_id)
        relation = PallasTrade::PaymentMethod.where(active: true)
        relation = relation.where(store_id: store_id) if store_id.present?
        relation
      end

      # 同级别不重复告警（级别升级或轮换后再次进入阈值会重新告警）。
      def alert?(payment_method, status)
        alerts = payment_method.metadata&.[]('credential_alerts')
        previous_level = alerts.is_a?(Hash) ? alerts.dig(status['key'], 'level') : nil
        previous_level != status['alert_level']
      end

      # metadata 是 `private_metadata` 的 API 别名 → 低层写用真实列名
      # （顺带避免触发 provider 校验/回调）。
      def persist_alert(payment_method, status, now)
        metadata = (payment_method.metadata || {}).dup
        alerts = metadata['credential_alerts'].is_a?(Hash) ? metadata['credential_alerts'].dup : {}
        alerts[status['key']] = { 'level' => status['alert_level'], 'alerted_at' => now.utc.iso8601 }
        metadata['credential_alerts'] = alerts

        payment_method.update_columns(private_metadata: metadata)

        PallasTrade::Audit.record(
          action: 'payment_method_credential_alert',
          resource: payment_method,
          metadata: {
            key: status['key'],
            level: status['alert_level'],
            days_left: status['days_left']
          }
        )
      end
    end
  end
end
