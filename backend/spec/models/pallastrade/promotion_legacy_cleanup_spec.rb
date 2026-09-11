# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-promotions-promo-batch6-pr-p9-cleanup AC-001 AC-002
#
# v2 时代残留下线验收：`advertise` / `path` 两列（迁移移除）、零调用方的
# `PromotionHandler::Page`、`Product#possible_promotions`、以及仅服务该关联的
# `Product#cache_key_for_product` 片段。断言"已物理消失"，避免后续又长回来。
RSpec.describe 'Promotion legacy field removal (PR-P9-1)', type: :model do
  describe 'schema（AC-1）' do
    it 'removes advertise / path columns from pallastrade_promotions' do
      expect(PallasTrade::Promotion.column_names).not_to include('advertise')
      expect(PallasTrade::Promotion.column_names).not_to include('path')
    end

    it 'does not expose removed attributes on new records' do
      promotion = PallasTrade::Promotion.new

      expect(promotion).not_to respond_to(:advertise=)
      expect(promotion).not_to respond_to(:path=)
    end
  end

  describe 'dead API surface（AC-1）' do
    it 'removes the advertised scope' do
      expect(PallasTrade::Promotion).not_to respond_to(:advertised)
    end

    it 'removes the unused PromotionHandler::Page' do
      expect(PallasTrade::PromotionHandler.const_defined?(:Page, false)).to be(false)
    end

    it 'removes Product#possible_promotions' do
      expect(PallasTrade::Product.new).not_to respond_to(:possible_promotions)
    end

    it 'stops permitting path / advertise in promotion attributes' do
      permitted = PallasTrade::PermittedAttributes.promotion_attributes

      expect(permitted).not_to include(:path)
      expect(permitted).not_to include(:advertise)
      expect(permitted).to include(:promotion_category_id)
    end
  end

  describe 'behavior preserved（AC-1：无 path 也能建/克隆）' do
    let(:store) { create(:store, code: 'promo_cleanup_store') }

    it 'creates a promotion' do
      promotion = create(:promotion, store: store, name: 'Cleanup Check', kind: :automatic)

      expect(promotion).to be_persisted
      expect(promotion.reload.name).to eq('Cleanup Check')
    end

    it 'duplicates a promotion without touching path' do
      # coupon_code 促销（automatic 促销会被 before_validation 置空 code）
      promotion = create(:promotion, store: store, name: 'Clone Source', code: 'CLEANUP1')

      clone = PallasTrade::PromotionHandler::PromotionDuplicator.new(promotion, random_string: 'abcd').duplicate

      expect(clone).to be_persisted
      expect(clone.name).to eq('New Clone Source')
      expect(clone.code).to eq('cleanup1_abcd')
    end

    it 'keeps the free-shipping handler query working without the path condition' do
      order = create(:order, store: store)

      expect { PallasTrade::PromotionHandler::FreeShipping.new(order).activate }.not_to raise_error
    end
  end

  # PRD-20260911-promotions-promo-batch6-pr-p9-cleanup (AC-006)
  # 知识同步门：本批次契约已写入 Skill 与 eval 场景，且 PRD 已入库。
  # 容器内未挂载 monorepo 根，文档类断言在容器运行时会跳过（由 doc-impact / sync-check 覆盖）。
  describe 'knowledge sync artifacts' do
    let(:repo_root) do
      candidate = Rails.root
      candidate = candidate.parent until candidate.root? || Dir.exist?(candidate.join('ai/skills'))
      candidate
    end

    it 'promotions/data-model Skill 记录了字段下线与分类后台' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('ai/skills'))

      expectations = {
        'pallastrade-promotions' => 'promotion_categories',
        'pallastrade-admin' => 'Promotions → Categories',
        'pallastrade-data-model' => 'advertise'
      }

      expectations.each do |skill, needle|
        path = repo_root.join("ai/skills/#{skill}/SKILL.md")

        expect(path).to exist
        expect(File.read(path)).to include(needle)
      end
    end

    it '注册了 GS-090 eval 场景与 PRD 文件' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('harness/scenarios'))

      scenarios = JSON.parse(File.read(repo_root.join('harness/scenarios/scenarios.json')))
      ids = (scenarios['scenarios'] || scenarios).map { |scenario| scenario['id'] }

      expect(ids).to include('GS-090')
      expect(repo_root.join('docs/prd/promotions/PRD-20260911-promotions-promo-batch6-pr-p9-cleanup.md')).to exist
    end
  end
end
