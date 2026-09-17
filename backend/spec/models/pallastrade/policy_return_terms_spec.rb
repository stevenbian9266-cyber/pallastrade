# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-json-ld-phase2 AC-009 AC-010 AC-011 AC-012 AC-014
#
# 结构化退货条款（商品页结构化数据 `hasMerchantReturnPolicy` 的数据源）的判定与归一化。
#
# 这一层是**唯一**的归一化入口：后台输入是自由文本，脏值（拼错的枚举、0 或负的天数、
# 重复的国家码）必须在这里收敛掉，否则会把一条「有限窗口但没说多少天」的**残缺政策**
# 喂给搜索引擎 —— 那比不输出更糟。
RSpec.describe PallasTrade::Policy, type: :model do
  let(:store) { create(:store, code: 'json_ld_phase2_model') }

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

  describe '#merchant_return_policy_terms' do
    it 'is nil while nothing is configured (AC-009)' do
      expect(returns_policy.merchant_return_policy_terms).to be_nil
    end

    it 'is nil for a finite window without days (AC-010)' do
      returns_policy.preferred_merchant_return_policy_category = 'finite_window'
      returns_policy.preferred_merchant_return_policy_days = nil

      expect(returns_policy.merchant_return_policy_terms).to be_nil
    end

    it 'is nil for a finite window with a non-positive day count (AC-010)' do
      returns_policy.preferred_merchant_return_policy_category = 'finite_window'
      returns_policy.preferred_merchant_return_policy_days = 0

      expect(returns_policy.merchant_return_policy_terms).to be_nil
    end

    it 'is nil when the category is not recognised (AC-010)' do
      returns_policy.preferred_merchant_return_policy_category = 'telepathy'

      expect(returns_policy.merchant_return_policy_terms).to be_nil
    end

    it 'normalises free-text enums and country codes (AC-011/AC-012)' do
      returns_policy.preferred_merchant_return_policy_category = ' finite_window '
      returns_policy.preferred_merchant_return_policy_days = 30
      returns_policy.preferred_merchant_return_policy_method = 'By_Mail '
      returns_policy.preferred_merchant_return_policy_fees = 'FREE'
      returns_policy.preferred_merchant_return_policy_countries = ' us , ca ,us '

      expect(returns_policy.merchant_return_policy_terms).to eq(
        category: 'finite_window',
        days: 30,
        method: 'by_mail',
        fees: 'free',
        countries: %w[US CA]
      )
    end

    it 'treats an unrecognised method or fee as "not configured" (AC-011)' do
      returns_policy.preferred_merchant_return_policy_category = 'finite_window'
      returns_policy.preferred_merchant_return_policy_days = 14
      returns_policy.preferred_merchant_return_policy_method = 'telepathy'
      returns_policy.preferred_merchant_return_policy_fees = 'whatever'

      terms = returns_policy.merchant_return_policy_terms

      expect(terms[:method]).to be_nil
      expect(terms[:fees]).to be_nil
    end

    it 'drops the day count outside a finite window (AC-011)' do
      returns_policy.preferred_merchant_return_policy_category = 'unlimited_window'
      returns_policy.preferred_merchant_return_policy_days = 30

      expect(returns_policy.merchant_return_policy_terms[:days]).to be_nil
    end

    it 'keeps the structured terms independent of the product it is shown on' do
      # 条款是**店级**事实，不随商品变化 —— 这里把它钉住，避免以后被误改成商品维度。
      returns_policy.preferred_merchant_return_policy_category = 'not_permitted'

      expect(returns_policy.merchant_return_policy_terms[:category]).to eq('not_permitted')
    end
  end

  describe '#returns_policy?' do
    it 'recognises the store return policy and nothing else (AC-014)' do
      expect(returns_policy.returns_policy?).to be(true)
      expect(privacy_policy.returns_policy?).to be(false)
    end

    it 'stays true no matter which locale the admin UI runs in (AC-014)' do
      # 回归防线：Mobility 会给未翻译的语言留下一行**空翻译**，而空行会遮住
      # `column_fallback` —— 直接读 `name` 在中文界面下会得到 nil，
      # 于是这个判定变成 false，商家就会**看不到**该填的结构化条款字段。
      expect(I18n.with_locale(:'zh-CN') { returns_policy.returns_policy? }).to be(true)
      expect(I18n.with_locale(:'zh-CN') { privacy_policy.returns_policy? }).to be(false)
      expect(I18n.with_locale(:fr) { returns_policy.returns_policy? }).to be(true)
    end

    it 'is false for a policy that merely mentions returns in its body' do
      stray = store.policies.create!(name: 'Returns FAQ')

      expect(stray.returns_policy?).to be(false)
    end
  end
end
