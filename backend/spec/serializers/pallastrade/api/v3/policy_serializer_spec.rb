# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-json-ld-phase2 AC-009 AC-010 AC-011 AC-012 AC-013 AC-007
#
# 结构化退货条款的 API 下发口径：只有**退货政策**、且条款**完整**时才有值；
# 其余一律 nil，让前台整体省略 `hasMerchantReturnPolicy`。
RSpec.describe PallasTrade::Api::V3::PolicySerializer, type: :serializer do
  let(:store) { create(:store, code: 'json_ld_phase2_serializer') }

  let(:returns_policy) do
    store.policies.with_matching_name(
      I18n.t('pallastrade.returns_policy', locale: :en)
    ).first
  end

  let(:privacy_policy) do
    store.policies.with_matching_name(
      I18n.t('pallastrade.privacy_policy', locale: :en)
    ).first
  end

  def serialize(policy)
    described_class.new(policy, params: {}).to_h
  end

  def configure_terms!(policy, **overrides)
    policy.update!(
      {
        preferred_merchant_return_policy_category: 'finite_window',
        preferred_merchant_return_policy_days: 30,
        preferred_merchant_return_policy_method: 'by_mail',
        preferred_merchant_return_policy_fees: 'free',
        preferred_merchant_return_policy_countries: 'US'
      }.merge(overrides)
    )
  end

  it 'ships no terms before they are configured (AC-009)' do
    expect(serialize(returns_policy)['merchant_return_policy']).to be_nil
  end

  it 'withholds a finite-window policy that carries no days (AC-010)' do
    configure_terms!(returns_policy, preferred_merchant_return_policy_days: nil)

    expect(serialize(returns_policy)['merchant_return_policy']).to be_nil
  end

  it 'withholds a policy whose category is not recognised (AC-010)' do
    configure_terms!(
      returns_policy,
      preferred_merchant_return_policy_category: 'telepathy'
    )

    expect(serialize(returns_policy)['merchant_return_policy']).to be_nil
  end

  it 'serializes normalised terms once they are complete (AC-011/AC-012)' do
    configure_terms!(
      returns_policy,
      preferred_merchant_return_policy_method: 'By_Mail ',
      preferred_merchant_return_policy_fees: 'FREE',
      preferred_merchant_return_policy_countries: ' us , ca ,us '
    )

    expect(serialize(returns_policy)['merchant_return_policy']).to eq(
      category: 'finite_window',
      days: 30,
      method: 'by_mail',
      fees: 'free',
      countries: %w[US CA]
    )
  end

  it 'never publishes terms for a policy other than the return policy (AC-013)' do
    # 就算有人把值写到了别的政策上，也不能出现在它的响应里 ——
    # 否则前台会拿一条挂错地方的数据当全店退货政策发布出去。
    configure_terms!(privacy_policy)

    expect(serialize(privacy_policy)['merchant_return_policy']).to be_nil
  end

  it 'keeps the pre-existing attributes untouched (AC-007 regression)' do
    payload = serialize(returns_policy)

    expect(payload.keys).to contain_exactly(
      'id', 'name', 'slug', 'body', 'body_html', 'merchant_return_policy'
    )
    expect(payload['name']).to eq(returns_policy.name)
    expect(payload['slug']).to eq('returns-policy')
  end
end
