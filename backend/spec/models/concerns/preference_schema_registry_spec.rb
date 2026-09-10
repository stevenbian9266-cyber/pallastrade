# frozen_string_literal: true

require 'spec_helper'

# PRD-20260910-promotions-promo-batch5a-definition-registry AC-007
# `PreferenceSchema.registered_subclasses` must resolve promotion rules/actions
# through the shared definition registry, and leave every other STI parent
# (PaymentMethod providers) untouched.
RSpec.describe PallasTrade::PreferenceSchema do
  describe 'PallasTrade::PromotionRule' do
    it 'resolves through the definition registry' do
      registered = PallasTrade::PromotionRule.send(:registered_subclasses)

      expect(registered).to eq(PallasTrade::Promotions::DefinitionRegistry.rule_classes)
      expect(registered).to eq(PallasTrade.promotions.rules)
      expect(registered).to include(PallasTrade::Promotion::Rules::Taxon)
    end

    it 'keeps /types output identical to the registry projection' do
      rows = PallasTrade::PromotionRule.subclasses_with_preference_schema

      expect(rows.map { |row| row[:type] }).
        to match_array(PallasTrade::Promotions::DefinitionRegistry.keys(:rule))
      expect(rows.size).to eq(PallasTrade::Promotions::DefinitionRegistry.rule_entries.size)
      expect(rows).to all(include(:type, :label, :description, :preference_schema))
    end

    it 'resolves shorthands through the registry' do
      expect(PallasTrade::PromotionRule.find_by_api_type('category')).to eq(PallasTrade::Promotion::Rules::Taxon)
      expect(PallasTrade::PromotionRule.find_by_api_type('customer')).to eq(PallasTrade::Promotion::Rules::User)
      expect(PallasTrade::PromotionRule.find_by_api_type('nope')).to be_nil
    end

    it 'picks up runtime registrations (extensions keep working)' do
      extra = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_runtime_rule'
        end
      end
      PallasTrade.promotions.rules << extra

      begin
        expect(PallasTrade::PromotionRule.send(:registered_subclasses)).to include(extra)
        expect(PallasTrade::PromotionRule.find_by_api_type('spec_runtime_rule')).to eq(extra)
      ensure
        PallasTrade.promotions.rules.delete(extra)
      end
    end
  end

  describe 'PallasTrade::PromotionAction' do
    it 'resolves through the definition registry' do
      registered = PallasTrade::PromotionAction.send(:registered_subclasses)

      expect(registered).to eq(PallasTrade::Promotions::DefinitionRegistry.action_classes)
      expect(registered).to eq(PallasTrade.promotions.actions)
    end

    it 'keeps every promoted action discoverable by shorthand' do
      expect(PallasTrade::PromotionAction.subclasses_with_preference_schema.map { |row| row[:type] }).
        to match_array(PallasTrade::Promotions::DefinitionRegistry.keys(:action))
    end
  end

  describe 'other STI parents (unchanged behaviour)' do
    it 'still uses the provider registry for PaymentMethod' do
      expect(PallasTrade::PaymentMethod.send(:registered_subclasses)).to eq(PallasTrade.payment_methods)
    end

    it 'returns an empty list for classes without a registry' do
      klass = Class.new do
        include PallasTrade::PreferenceSchema
      end

      expect(klass.send(:registered_subclasses)).to eq([])
    end
  end
end
