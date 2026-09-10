# frozen_string_literal: true

require 'spec_helper'

# PRD-20260910-promotions-promo-batch5a-definition-registry AC-001 AC-002 AC-003 AC-004 AC-005 AC-008
#
# PR-P7-1 registry projection + PR-P7-3 validation.
RSpec.describe PallasTrade::Promotions::DefinitionRegistry do
  let(:registry) { described_class }

  describe 'registered entries (AC-001)' do
    it 'projects every registered rule and action' do
      expect(registry.rule_entries.size).to eq(PallasTrade.promotions.rules.size)
      expect(registry.action_entries.size).to eq(PallasTrade.promotions.actions.size)
      expect(registry.rule_entries.size).to eq(13)
      expect(registry.action_entries.size).to eq(4)
    end

    it 'maps key / type / kind for a rule' do
      entry = registry.entry_for('PallasTrade::Promotion::Rules::Currency')

      expect(entry.key).to eq('currency')
      expect(entry.type).to eq('PallasTrade::Promotion::Rules::Currency')
      expect(entry.kind).to eq(:rule)
      expect(entry).to be_rule
      expect(entry).not_to be_action
    end

    it 'keeps the api_type renames for Taxon and User (category / customer)' do
      taxon = registry.entry_for('category')
      user = registry.entry_for('customer')

      expect(taxon.klass).to eq(PallasTrade::Promotion::Rules::Taxon)
      expect(user.klass).to eq(PallasTrade::Promotion::Rules::User)
      expect(taxon.admin_partial).to eq('pallastrade/admin/promotion_rules/forms/category')
      expect(taxon.locale_key).to eq('promotion_rule_types.category')
    end

    it 'maps calculator-backed actions and leaves non-calculator actions without a requirement' do
      adjustment = registry.entry_for('PallasTrade::Promotion::Actions::CreateAdjustment')
      free_shipping = registry.entry_for('free_shipping')

      expect(adjustment).to be_calculator_required
      expect(adjustment.calculator_types).to include('PallasTrade::Calculator::FlatRate')
      expect(free_shipping).not_to be_calculator_required
      expect(free_shipping.calculators).to eq([])
      expect(free_shipping.admin_partial).to eq('pallastrade/admin/promotion_actions/forms/free_shipping')
    end

    it 'exposes labels/descriptions from the same locale keys the admin reads' do
      expect(registry.entry_for('category').label).to eq('Categories')
      expect(registry.entry_for('customer').label).to eq('Customers')
      expect(registry.entry_for('category').description).to be_present
    end
  end

  describe 'capability projection (AC-002)' do
    it 'matches the calculator buckets registered on PallasTrade.calculators' do
      order_level = registry.calculators_for('PallasTrade::Promotion::Actions::CreateAdjustment')
      item_level = registry.calculators_for('PallasTrade::Promotion::Actions::CreateItemAdjustments')

      expect(order_level).to eq(PallasTrade.calculators.promotion_actions_create_adjustments)
      expect(item_level).to eq(PallasTrade.calculators.promotion_actions_create_item_adjustments)
    end

    it 'matches additional_permitted_attributes for the API param allowlist' do
      taxon = registry.entry_for('PallasTrade::Promotion::Rules::Taxon')
      user = registry.entry_for('PallasTrade::Promotion::Rules::User')
      product = registry.entry_for('PallasTrade::Promotion::Rules::Product')

      expect(taxon.allowed_attributes).to eq(PallasTrade::Promotion::Rules::Taxon.additional_permitted_attributes)
      expect(taxon.allowed_attributes).to eq([{ category_ids: [] }])
      expect(user.allowed_attributes).to eq([{ customer_ids: [] }])
      expect(product.allowed_attributes).to eq([{ product_ids: [] }])
    end

    it 'returns an empty capability list for rules (no calculators)' do
      expect(registry.calculators_for('currency')).to eq([])
    end
  end

  describe 'lookup (AC-003)' do
    it 'resolves shorthands, class names and classes' do
      klass = PallasTrade::Promotion::Rules::Taxon

      expect(registry.find_by_api_type('category')).to eq(klass)
      expect(registry.find_by_api_type(klass.to_s)).to eq(klass)
      expect(registry.entry_for(klass).key).to eq('category')
      expect(registry.api_type_for(klass)).to eq('category')
      expect(registry.kind_for(klass)).to eq(:rule)
      expect(registry.kind_for('PallasTrade::Promotion::Actions::FreeShipping')).to eq(:action)
    end

    it 'returns nil for unknown input' do
      expect(registry.find_by_api_type('not_a_real_rule')).to be_nil
      expect(registry.entry_for('PallasTrade::Fake::Rule')).to be_nil
      expect(registry.entry_for(nil)).to be_nil
    end

    it 'scopes lookups by kind' do
      rule_view = registry.for(:rule)
      action_view = registry.for(:action)

      expect(rule_view.find_by_api_type('category')).to eq(PallasTrade::Promotion::Rules::Taxon)
      expect(rule_view.find_by_api_type('free_shipping')).to be_nil
      expect(action_view.find_by_api_type('free_shipping')).to eq(PallasTrade::Promotion::Actions::FreeShipping)
      expect(action_view.classes).to eq(PallasTrade.promotions.actions)
      expect(rule_view.keys).to eq(registry.rule_entries.map(&:key))
    end

    it 'rejects an unknown kind' do
      expect { registry.for(:coupon) }.to raise_error(ArgumentError, /Unknown promotion definition kind/)
    end

    it 'reads the live registration arrays (no stale cache)' do
      extra = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_extra_rule'
        end
      end
      PallasTrade.promotions.rules << extra

      begin
        expect(registry.find_by_api_type('spec_extra_rule')).to eq(extra)
        expect(registry.keys(:rule)).to include('spec_extra_rule')
      ensure
        PallasTrade.promotions.rules.delete(extra)
      end

      expect(registry.find_by_api_type('spec_extra_rule')).to be_nil
    end
  end

  describe 'validation of the shipped registry (AC-004)' do
    it 'reports no errors for the default rule/action set' do
      errors = registry.validate!.select { |issue| issue[:level] == :error }

      expect(errors).to eq([])
      expect(registry).to be_valid
    end

    it 'returns issues as { level:, code:, key:, kind:, message: }' do
      expect(registry.validate!).to all(include(:level, :code, :key, :kind, :message))
    end

    it 'declares a severity for every validation code' do
      expect(described_class::VALIDATION_CODES.values.uniq).to contain_exactly(:error, :warning)
    end
  end

  describe 'validation of synthetic gaps (AC-005)' do
    def issues_for(klass, kind: :rule)
      registry.validate!(kinds: [kind], classes: [klass])
    end

    it 'flags a duplicated api_type as an error' do
      klass = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'category'
        end
      end

      issue = described_class.validate!(kinds: [:rule],
                                        classes: [PallasTrade::Promotion::Rules::Taxon, klass]).
              find { |row| row[:code] == :duplicate_api_type }

      expect(issue[:level]).to eq(:error)
      expect(issue[:key]).to eq('category')
      expect(issue[:message]).to include('category')
    end

    it 'flags a class that does not inherit the STI parent' do
      klass = Class.new do
        def self.api_type
          'bogus_rule'
        end
      end

      issue = issues_for(klass).find { |row| row[:code] == :invalid_sti_parent }

      expect(issue[:level]).to eq(:error)
      expect(issue[:key]).to eq('bogus_rule')
    end

    it 'flags a missing admin form partial' do
      klass = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_rule_without_partial'
        end
      end

      issue = issues_for(klass).find { |row| row[:code] == :missing_admin_partial }

      expect(issue[:level]).to eq(:error)
      expect(issue[:message]).to include('pallastrade/admin/promotion_rules/forms/spec_rule_without_partial')
    end

    it 'flags an empty calculator bucket for a calculator-backed action' do
      klass = Class.new(PallasTrade::Promotion::Actions::CreateAdjustment) do
        def self.calculators
          []
        end
      end

      issue = issues_for(klass, kind: :action).find { |row| row[:code] == :missing_calculator }

      expect(issue[:level]).to eq(:error)
      expect(issue[:message]).to include('PallasTrade.calculators')
    end

    it 'flags a non-array additional_permitted_attributes' do
      klass = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_rule_bad_attrs'
        end

        def self.additional_permitted_attributes
          { category_ids: [] }
        end
      end

      issue = issues_for(klass).find { |row| row[:code] == :invalid_allowed_attributes }

      expect(issue[:level]).to eq(:error)
      expect(issue[:message]).to include('must return an Array')
    end

    it 'flags a missing locale label as a warning only' do
      klass = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_rule_without_locale'
        end
      end

      issue = issues_for(klass).find { |row| row[:code] == :missing_locale }

      expect(issue[:level]).to eq(:warning)
      expect(issue[:message]).to include('promotion_rule_types.spec_rule_without_locale')
    end

    it 'flags an STI subclass that was never registered as a warning' do
      stub_const('SpecUnregisteredPromotionRule',
                 Class.new(PallasTrade::PromotionRule) do
                   def self.api_type
                     'spec_unregistered_rule'
                   end
                 end)

      issue = issues_for(PallasTrade::Promotion::Rules::Currency).
              find { |row| row[:code] == :unregistered_class && row[:message].include?('SpecUnregisteredPromotionRule') }

      expect(issue[:level]).to eq(:warning)
      expect(issue[:message]).to include('SpecUnregisteredPromotionRule')
    end
  end
  # PRD-20260910-promotions-promo-batch5a-definition-registry (AC-008)
  # Knowledge-sync / regression gate: the batch is only complete when the
  # registry stayed consistent AND the skills + eval scenario + PRD shipped.
  # The monorepo root is not mounted when the suite runs inside the backend
  # container, so the documentation half is skipped there (doc-impact + prd
  # verify cover it in that runtime).
  describe 'knowledge sync artifacts' do
    let(:repo_root) do
      candidate = Rails.root
      candidate = candidate.parent until candidate.root? || Dir.exist?(candidate.join('ai/skills'))
      candidate
    end

    it 'keeps the shipped registry consistent (regression gate)' do
      errors = PallasTrade::Promotions::DefinitionRegistry.validate!.select { |issue| issue[:level] == :error }

      expect(errors).to eq([])
    end

    it 'documents the registry in the promotion/api/admin/customization skills' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('ai/skills'))

      %w[pallastrade-promotions pallastrade-api-v3 pallastrade-admin pallastrade-customization].each do |skill|
        path = repo_root.join("ai/skills/#{skill}/SKILL.md")

        expect(path).to exist
        expect(File.read(path)).to include('DefinitionRegistry')
      end
    end

    it 'registers the GS-088 eval scenario and the PRD itself' do
      skip 'monorepo root is not mounted in this runtime' unless Dir.exist?(repo_root.join('harness/scenarios'))

      scenarios = JSON.parse(File.read(repo_root.join('harness/scenarios/scenarios.json')))
      ids = (scenarios['scenarios'] || scenarios).map { |scenario| scenario['id'] }

      expect(ids).to include('GS-088')
      expect(repo_root.join('docs/prd/promotions/PRD-20260910-promotions-promo-batch5a-definition-registry.md')).to exist
    end
  end
end
