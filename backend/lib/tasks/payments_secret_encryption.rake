# frozen_string_literal: true

# P0-5 (PRD FR-053): Gateway preferences 渐进加密 backfill / verify。
#
# 前置：ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / DETERMINISTIC_KEY / KEY_DERIVATION_SALT
# 已在进程 ENV 配置（否则 encrypts 惰性、task 为 no-op）。
#
#   bundle exec rake pallastrade:payments:encrypt_preferences
#   bundle exec rake pallastrade:payments:verify_encrypted_preferences
#
# 幂等：对已加密行 decrypt→re-encrypt，安全重复执行；非 destructive。
namespace :pallastrade do
  namespace :payments do
    desc 'P0-5: backfill gateway PaymentMethod.preferences to AR-encrypted ciphertext (idempotent)'
    task encrypt_preferences: :environment do
      unless Rails.configuration.active_record.encryption.include?(:primary_key)
        puts '[p0-5] AR encryption not configured (ACTIVE_RECORD_ENCRYPTION_* missing) — no-op.'
        next
      end

      total = 0
      PallasTrade::Gateway.find_each do |gateway|
        next if gateway.preferences.blank?

        gateway.update!(preferences: gateway.preferences)
        total += 1
      end
      puts "[p0-5] Backfilled #{total} gateway payment methods."
    end

    desc 'P0-5: verify no plaintext gateway secrets (sk_/whsec_) remain in the preferences column'
    task verify_encrypted_preferences: :environment do
      leaks = []
      PallasTrade::Gateway.find_each do |gateway|
        raw = gateway.read_attribute(:preferences).to_s
        leaks << gateway.id if raw.match?(/sk_(test|live)_|whsec_/)
      end

      if leaks.empty?
        puts '[p0-5] OK: no plaintext gateway secrets in preferences.'
      else
        puts "[p0-5] LEAK: #{leaks.size} rows still contain plaintext secrets: #{leaks.first(20).join(',')}"
        exit 1
      end
    end
  end
end
