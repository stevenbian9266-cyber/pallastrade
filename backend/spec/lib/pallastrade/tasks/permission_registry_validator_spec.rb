# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# 任务类定义在 gem 的 rake 文件里（与 promotions.rake 同模式），测试前显式加载。
load Rails.root.join('pallastrade_gems/pallastrade_core/lib/tasks/permissions.rake')

# PRD-20260911-promotions-promo-batch5b-permission-single-source AC-006
# `pallastrade:permissions:validate` 报告 + STRICT 退出行为。
RSpec.describe PallasTrade::Tasks::PermissionRegistryValidator do
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe '真实注册表' do
    it '报告资源/模型计数且无 error' do
      output = capture_stdout { described_class.new.call }

      # 计数取自注册表本身（而非写死数字）：新增 capability（如 batch6 的
      # :promotion_categories）不应打破本断言，只校验"报告与注册表一致 + 无 error"。
      registry = PallasTrade::PermissionRegistry
      expected_models = registry.resources.sum { |resource| Array(registry[resource]&.models).size }

      expect(output).to include("resources=#{registry.resources.size}")
      expect(output).to include("models=#{expected_models}")
      expect(output).to include('errors=0')
      expect(output).not_to include('ERROR issues:')
    end
  end

  describe '注入伪造注册表' do
    let(:fake_registry_class) do
      Class.new do
        def initialize(resources, issues)
          @resources = resources
          @issues = issues
        end

        attr_reader :resources

        def [](_resource)
          nil
        end

        def validate!
          @issues
        end
      end
    end

    let(:error_issue) do
      { level: :error, code: :invalid_data_field, resource: :broken,
        message: '资源 :broken 的数据字段 "nope" 不是真实列' }
    end

    let(:warning_issue) do
      { level: :warning, code: :resource_without_model, resource: :ui_only, message: 'UI-only 资源' }
    end

    it '返回 error 计数并逐条打印' do
      task = described_class.new(strict: false, registry: fake_registry_class.new([:broken, :ui_only], [error_issue, warning_issue]))

      errors = nil
      output = capture_stdout { errors = task.call }

      expect(errors).to eq(1)
      expect(output).to include('resources=2')
      expect(output).to include('errors=1 warnings=1')
      expect(output).to include('[invalid_data_field] broken')
      expect(output).to include('[resource_without_model] ui_only')
    end

    it 'STRICT=1 且有 error 时抛错' do
      task = described_class.new(strict: true, registry: fake_registry_class.new([:broken], [error_issue]))

      expect { capture_stdout { task.call } }.
        to raise_error(RuntimeError, /1 permission registry error\(s\)/)
    end

    it 'STRICT=1 但只有 warning 时不抛错' do
      task = described_class.new(strict: true, registry: fake_registry_class.new([:ui_only], [warning_issue]))

      errors = nil
      output = capture_stdout { errors = task.call }

      expect(errors).to eq(0)
      expect(output).to include('errors=0 warnings=1')
    end
  end

  describe 'rake 接线' do
    it '注册了 pallastrade:permissions:validate' do
      expect(Rake::Task.task_defined?('pallastrade:permissions:validate')).to be(true)
    end
  end
end
