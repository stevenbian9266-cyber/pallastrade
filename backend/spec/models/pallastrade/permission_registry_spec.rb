# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-promotions-promo-batch5b-permission-single-source AC-001 AC-004 AC-006 AC-007
# 权限注册表：capability（资源）→ 覆盖模型集合；矩阵/Ability/nav 校验的单一事实源。
RSpec.describe PallasTrade::PermissionRegistry do
  # 本 spec 会注册/删除测试资源，结束时按快照还原，避免污染其他用例。
  around do |example|
    snapshot = described_class.snapshot
    example.run
  ensure
    described_class.replace_entries!(snapshot)
  end

  describe '多模型覆盖（AC-001）' do
    it '未声明 models 时回落到 [model_class]' do
      described_class.register(:spec_orders, model_class: PallasTrade::Order, data_fields: %w[store_id])

      entry = described_class[:spec_orders]
      expect(entry.models).to eq([PallasTrade::Order])
      expect(entry.model_class).to eq(PallasTrade::Order)
    end

    it 'promotions 覆盖促销三个后台模型，model_class 保持主模型' do
      entry = described_class[:promotions]

      expect(entry.models).to contain_exactly(PallasTrade::Promotion,
                                              PallasTrade::PromotionRule,
                                              PallasTrade::PromotionAction)
      expect(entry.model_class).to eq(PallasTrade::Promotion)
      expect(entry.models.first).to eq(entry.model_class)
    end

    it 'coupon_codes 资源已注册且单独覆盖 CouponCode（AC-004）' do
      entry = described_class[:coupon_codes]

      expect(entry).to be_present
      expect(entry.models).to eq([PallasTrade::CouponCode])
      expect(entry.actions).to include('read', 'create', 'update', 'destroy')
    end

    it '按模型反查覆盖它的资源' do
      expect(described_class.resources_for_model(PallasTrade::PromotionRule)).to include(:promotions)
      expect(described_class.resources_for_model(PallasTrade::CouponCode)).to include(:coupon_codes)
      expect(described_class.resources_for_model(PallasTrade::PromotionRedemption)).to include(:promotion_redemptions)
    end
  end

  describe '促销后台 surface 覆盖（AC-007）' do
    it '后台促销相关模型均被某个 capability 覆盖（与 nav:validate 同一判定）' do
      covered = described_class.resources.flat_map { |resource| described_class[resource].models.map(&:name) }

      expect(covered).to include('PallasTrade::Promotion',
                                 'PallasTrade::PromotionRule',
                                 'PallasTrade::PromotionAction',
                                 'PallasTrade::CouponCode',
                                 'PallasTrade::PromotionRedemption')
    end
  end

  describe '注册表自洽校验（AC-006）' do
    it '默认真实注册表无 error（UI-only 资源仅告警）' do
      issues = described_class.validate!

      expect(issues.select { |issue| issue[:level] == :error }).to eq([])
      expect(issues.select { |issue| issue[:code] == :resource_without_model }.map { |i| i[:resource] }).
        to include(:reports, :emails, :developers)
      expect(described_class).to be_valid
    end

    it '每条 issue 带 level/code/resource/message' do
      described_class.register(:spec_broken, model_class: String, actions: %w[read explode], data_fields: %w[nope])

      described_class.validate!.each do |issue|
        expect(issue).to include(:level, :code, :resource, :message)
      end
    end

    it '非 AR 模型 → invalid_model_class（error）' do
      described_class.register(:spec_bad_model, model_class: String)

      issue = described_class.validate!.find { |row| row[:code] == :invalid_model_class }
      expect(issue[:level]).to eq(:error)
      expect(issue[:resource]).to eq(:spec_bad_model)
    end

    it 'model_class 与 models.first 不一致 → model_class_mismatch（error）' do
      described_class.register(:spec_mismatch, model_class: PallasTrade::Order,
                                               models: [PallasTrade::Product])

      issue = described_class.validate!.find { |row| row[:code] == :model_class_mismatch }
      expect(issue[:level]).to eq(:error)
    end

    it '非法动作 → invalid_action（error）' do
      described_class.register(:spec_bad_action, model_class: PallasTrade::Order, actions: %w[read explode])

      issue = described_class.validate!.find { |row| row[:code] == :invalid_action }
      expect(issue[:level]).to eq(:error)
      expect(issue[:message]).to include('explode')
    end

    it '数据字段不是任何覆盖模型的列且不可达 → invalid_data_field（error）' do
      described_class.register(:spec_bad_field, model_class: PallasTrade::PromotionCategory,
                                                data_fields: %w[store_id])

      issue = described_class.validate!.find { |row| row[:code] == :invalid_data_field }
      expect(issue[:level]).to eq(:error)
      expect(issue[:resource]).to eq(:spec_bad_field)
    end

    it '经 belongs_to 可达的数据字段不算错误（CouponCode → promotion.store_id）' do
      issues = described_class.validate!.select { |row| row[:resource] == :coupon_codes }

      expect(issues).to eq([])
    end

    it '覆盖模型缺列且无关联路径 → missing_data_scope_path（error）' do
      described_class.register(:spec_mixed, model_class: PallasTrade::Promotion,
                                            models: [PallasTrade::Promotion, PallasTrade::PromotionCategory],
                                            data_fields: %w[store_id])

      issue = described_class.validate!.find do |row|
        row[:code] == :missing_data_scope_path && row[:resource] == :spec_mixed
      end
      expect(issue[:level]).to eq(:error)
      expect(issue[:message]).to include('PromotionCategory')
    end

    it '同一模型被多个资源覆盖 → duplicate_model（warning）' do
      described_class.register(:spec_duplicate, model_class: PallasTrade::Promotion, data_fields: %w[store_id])

      issue = described_class.validate!.find { |row| row[:code] == :duplicate_model }
      expect(issue[:level]).to eq(:warning)
      expect(issue[:message]).to include('PallasTrade::Promotion')
    end

    it '无模型的 UI-only 资源只告警' do
      described_class.register(:spec_ui_only, model_class: nil, actions: %w[read])

      issue = described_class.validate!.find do |row|
        row[:code] == :resource_without_model && row[:resource] == :spec_ui_only
      end
      expect(issue[:level]).to eq(:warning)
    end
  end

  # PRD-20260911-promotions-promo-batch5b-permission-single-source (AC-008)
  # 知识同步门：本批次契约已写入 Skill 与 eval 场景，且 PRD 已入库。
  # 容器内未挂载 monorepo 根，文档类断言在容器运行时会跳过（由 doc-impact / sync-check 覆盖）。
  describe 'knowledge sync artifacts' do
    let(:repo_root) do
      candidate = Rails.root
      candidate = candidate.parent until candidate.root? || Dir.exist?(candidate.join('ai/skills'))
      candidate
    end

    it '权限与促销 Skill 记录了 capability 单源与校验命令' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('ai/skills'))

      expectations = {
        'pallastrade-admin' => 'permissions:validate',
        'pallastrade-security' => 'grants_registry_resource',
        'pallastrade-promotions' => 'coupon_codes'
      }

      expectations.each do |skill, needle|
        path = repo_root.join("ai/skills/#{skill}/SKILL.md")

        expect(path).to exist
        expect(File.read(path)).to include(needle)
      end
    end

    it '注册了 GS-089 eval 场景与 PRD 文件' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('harness/scenarios'))

      scenarios = JSON.parse(File.read(repo_root.join('harness/scenarios/scenarios.json')))
      ids = (scenarios['scenarios'] || scenarios).map { |scenario| scenario['id'] }

      expect(ids).to include('GS-089')
      expect(repo_root.join('docs/prd/promotions/PRD-20260911-promotions-promo-batch5b-permission-single-source.md')).to exist
    end
  end
end
