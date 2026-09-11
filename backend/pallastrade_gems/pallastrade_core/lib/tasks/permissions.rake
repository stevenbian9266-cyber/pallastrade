# frozen_string_literal: true

# PRD-20260911-promotions-promo-batch5b (PR-P8-3, AC-006): 权限注册表自洽校验。
#
#   bundle exec rake pallastrade:permissions:validate
#   STRICT=1 bundle exec rake pallastrade:permissions:validate   # 有 error 时非零退出
#
# 校验内容：资源声明的覆盖模型（models）是否为 AR 子类、动作是否在
# RolePermission::FUNCTION_ACTIONS 内、数据字段是否为覆盖模型的真实列（无该列时
# 能否经 belongs_to 上卷）、model_class 与 models.first 是否一致、模型是否被多个资源覆盖。
module PallasTrade
  module Tasks
    class PermissionRegistryValidator
      def initialize(strict: false, registry: PallasTrade::PermissionRegistry)
        @strict = strict
        @registry = registry
      end

      def call
        issues = @registry.validate!
        print_report(issues)

        errors = issues.count { |issue| issue[:level] == :error }
        if errors.positive? && @strict
          raise "#{errors} permission registry error(s) — see report above " \
                '(PRD-20260911-promotions-promo-batch5b AC-006)'
        end

        errors
      end

      private

      def print_report(issues)
        resources = @registry.resources
        models = resources.sum { |resource| Array(@registry[resource]&.models).size }

        puts "Permission registry: resources=#{resources.size} models=#{models} " \
             "errors=#{count(issues, :error)} warnings=#{count(issues, :warning)}"

        issues.group_by { |issue| issue[:level] }.each do |level, rows|
          puts "#{level.to_s.upcase} issues:"
          rows.each { |row| puts "  [#{row[:code]}] #{row[:resource]}: #{row[:message]}" }
        end

        puts 'Registry is consistent.' if issues.empty?
      end

      def count(issues, level)
        issues.count { |issue| issue[:level] == level }
      end
    end
  end
end

namespace :pallastrade do
  namespace :permissions do
    desc 'Validate PermissionRegistry (models/actions/data fields); STRICT=1 fails on errors (PRD-20260911-promo-batch5b)'
    task validate: :environment do
      PallasTrade::Tasks::PermissionRegistryValidator.new(strict: ENV['STRICT'].to_s == '1').call
    end
  end
end
