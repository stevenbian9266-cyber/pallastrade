# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# 任务类定义在 gem 的 rake 文件里（与 batch1/batch3a 一致），
# 测试前显式加载，避免 PallasTrade::Tasks 常量在 describe 时未定义。
load Rails.root.join('pallastrade_gems/pallastrade_core/lib/tasks/promotions.rake')

# PRD-20260910-promotions-promo-batch5a-definition-registry AC-006
# `pallastrade:promotions:definitions` reporting + STRICT exit behaviour.
RSpec.describe PallasTrade::Tasks::PromoDefinitionRegistryValidator do
  let(:registry) { PallasTrade::Promotions::DefinitionRegistry }

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe 'against the shipped registry' do
    it 'prints a grouped report with counts and no errors' do
      output = capture_stdout { described_class.new.call }

      expect(output).to include('Promotion definition registry: rules=13 actions=4')
      expect(output).to include('errors=0')
      expect(output).not_to include('[error]')
    end

    it 'does not raise without STRICT even when the registry would be inconsistent' do
      output = capture_stdout { described_class.new(strict: false).call }

      expect(output).to include('errors=0')
    end
  end

  describe 'with injected issues' do
    let(:fake_registry) do
      Class.new do
        def initialize(entries, issues)
          @entries = entries
          @issues = issues
        end

        attr_reader :entries

        def validate!
          @issues
        end
      end
    end

    let(:entries) do
      [
        build_entry(:rule, 'currency', 'PallasTrade::Promotion::Rules::Currency'),
        build_entry(:action, 'create_adjustment', 'PallasTrade::Promotion::Actions::CreateAdjustment')
      ]
    end

    let(:error_issue) do
      { level: :error, code: :missing_admin_partial, key: 'broken_rule', kind: :rule,
        message: 'missing admin form partial pallastrade/admin/promotion_rules/forms/broken_rule' }
    end

    let(:warning_issue) do
      { level: :warning, code: :missing_locale, key: 'currency', kind: :rule,
        message: 'missing locale key promotion_rule_types.currency.name' }
    end

    def build_entry(kind, key, type)
      PallasTrade::Promotions::DefinitionRegistry::Entry.new(
        key: key, type: type, kind: kind, klass: Object, label: key.titleize,
        description: nil, calculators: [], allowed_attributes: [],
        admin_partial: nil, locale_key: nil, calculator_required: false
      )
    end

    it 'returns the error count and prints every issue' do
      injected = fake_registry.new(entries, [error_issue, warning_issue])
      task = described_class.new(strict: false, registry: injected)

      errors = nil
      output = capture_stdout { errors = task.call }

      expect(errors).to eq(1)
      expect(output).to include('rules=1 actions=1 errors=1 warnings=1')
      expect(output).to include('RULE issues:')
      expect(output).to include('[error] missing_admin_partial broken_rule')
      expect(output).to include('[warning] missing_locale currency')
    end

    it 'raises under STRICT when errors are present' do
      injected = fake_registry.new(entries, [error_issue])
      task = described_class.new(strict: true, registry: injected)

      expect { capture_stdout { task.call } }.
        to raise_error(RuntimeError, /1 promotion definition error\(s\)/)
    end

    it 'stays silent under STRICT when only warnings are reported' do
      injected = fake_registry.new(entries, [warning_issue])
      task = described_class.new(strict: true, registry: injected)

      errors = nil
      output = capture_stdout { errors = task.call }

      expect(errors).to eq(0)
      expect(output).to include('errors=0 warnings=1')
    end
  end

  describe 'rake wiring' do
    it 'registers pallastrade:promotions:definitions' do
      rake = Rake::Task.task_defined?('pallastrade:promotions:definitions')

      expect(rake).to be(true)
    end
  end
end
