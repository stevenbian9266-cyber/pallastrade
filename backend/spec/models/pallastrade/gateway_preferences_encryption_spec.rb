# frozen_string_literal: true

require 'rails_helper'

# P0-5 (PRD FR-053, 方案 A): PallasTrade::Gateway#preferences 的 Active Record
# Encryption。默认（未注入 ACTIVE_RECORD_ENCRYPTION_*）下 encrypts 惰性 → skip；
# 注入密钥运行时验证：
#   - 写入后 DB 列不含明文 secret（密文落库）
#   - 读回透明解密（含 masked round-trip 语义不受影响）
#   - support_unencrypted_data=true → 历史明文行 dual-read 可用（backfill 窗口）
RSpec.describe 'PallasTrade::Gateway preferences encryption (P0-5)', type: :model do
  encryption_enabled = Rails.configuration.active_record.encryption.include?(:primary_key)

  before do
    skip 'AR encryption not configured (ACTIVE_RECORD_ENCRYPTION_*) — run this spec with keys' unless encryption_enabled
  end

  let(:store) { @default_store }
  let!(:gateway) do
    create(:stripe_gateway, store: store, active: true, display_on: 'both',
                            preferences: { secret_key: 'sk_test_p05', publishable_key: 'pk_test_p05' })
  end

  # preferences Hash 键在 DSL 中为符号（YAML 反序列化亦为符号）；稳妥起见两种键兼容取。
  def pref_secret(gw)
    hash = gw.reload.preferences
    hash[:secret_key] || hash['secret_key']
  end

  # 原生 SQL 读列值（read_attribute 会解密，不能用于密文断言）。
  def raw_preferences_column(gw)
    PallasTrade::PaymentMethod.connection.select_value(
      "SELECT preferences FROM pallastrade_payment_methods WHERE id = #{gw.id}"
    ).to_s
  end

  it 'stores gateway preferences as ciphertext (no plaintext secret in the column)' do
    raw = raw_preferences_column(gateway)
    expect(raw).not_to include('sk_test_p05')
    expect(raw).not_to include('pk_test_p05')
  end

  it 'reads back the decrypted secret transparently' do
    expect(pref_secret(gateway)).to eq('sk_test_p05')
  end

  it 'keeps masking + masked round-trip guard working on encrypted values' do
    masked = PallasTrade::Preferences::Masking.serialize(gateway)
    expect(masked['secret_key']).not_to include('sk_test_p05')
    expect(masked['publishable_key']).not_to include('pk_test_p05')
    # masked 值再提交不覆盖真实 Secret（SubclassedResource 守卫语义）
    expect(PallasTrade::Preferences::Masking.masked?(masked['secret_key'])).to be true
  end

  it 'supports dual-read of legacy plaintext rows (support_unencrypted_data=true)' do
    plaintext_yaml = YAML.dump({ secret_key: 'sk_legacy_plain' }).gsub("'", "''")
    PallasTrade::PaymentMethod.connection.execute(<<~SQL)
      UPDATE pallastrade_payment_methods
      SET preferences = '#{plaintext_yaml}'
      WHERE id = #{gateway.id}
    SQL

    expect(pref_secret(gateway)).to eq('sk_legacy_plain')
  end
end
