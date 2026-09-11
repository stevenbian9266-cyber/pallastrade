# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-promotions-promo-batch5b-permission-single-source AC-005
# 代码级权限集从 PermissionRegistry 派生（不再与注册表各写一份资源清单）。
RSpec.describe PallasTrade::PermissionSets::PromotionManagement do
  let(:ability) { PallasTrade::Ability.new(PallasTrade.user_class.new) }

  subject(:activated) do
    described_class.new(ability).activate!
    ability
  end

  it '声明了从注册表派生的资源（promotions / coupon_codes / promotion_redemptions）' do
    grants = described_class.registry_grants

    expect(grants.map(&:first).flatten).to contain_exactly(:promotions, :coupon_codes, :promotion_redemptions)
    expect(grants.find { |resources, _| resources.include?(:promotion_redemptions) }.last).to eq([:read])
  end

  it 'manage 覆盖 promotions 的全部模型' do
    PallasTrade::PermissionRegistry[:promotions].models.each do |model|
      expect(activated).to be_can(:manage, model)
    end
  end

  it 'manage 覆盖 coupon_codes 的模型' do
    PallasTrade::PermissionRegistry[:coupon_codes].models.each do |model|
      expect(activated).to be_can(:manage, model)
    end
  end

  it 'redemptions 只读（不授予写权限）' do
    expect(activated).to be_can(:read, PallasTrade::PromotionRedemption)
    expect(activated).not_to be_can(:update, PallasTrade::PromotionRedemption)
    expect(activated).not_to be_can(:destroy, PallasTrade::PromotionRedemption)
  end

  it '保留无后台矩阵入口的显式声明（PromotionCategory / Metafield）' do
    expect(activated).to be_can(:manage, PallasTrade::PromotionCategory)
    expect(activated).to be_can(:read, PallasTrade::Metafield)
    expect(activated).to be_can(:admin, PallasTrade::Metafield)
  end

  it '派生的授权集合与注册表覆盖集合一致（单一事实源）' do
    expected = PallasTrade::PermissionRegistry[:promotions].models +
      PallasTrade::PermissionRegistry[:coupon_codes].models

    expected.each { |model| expect(activated).to be_can(:manage, model) }
    expect(activated).not_to be_can(:manage, PallasTrade::Product)
    expect(activated).not_to be_can(:manage, PallasTrade::Order)
  end

  it '未声明注册表授权的权限集仍要求覆写 activate!（向后兼容）' do
    klass = Class.new(PallasTrade::PermissionSets::Base)

    expect { klass.new(ability).activate! }.to raise_error(NotImplementedError)
  end
end
