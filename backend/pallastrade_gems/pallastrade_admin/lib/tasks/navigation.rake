# frozen_string_literal: true

# PALLAS-CUSTOM: 管理后台导航 Schema 校验器（P5 导航架构重构）
#
# 用法：
#   bin/rails pallastrade:admin:nav_validate
#
# 校验「导航配置 = 唯一事实源」的 Schema 约束（docs/research/admin-navigation-refactor-plan.md §4）：
#   1. 顶级项必须声明 icon，且 URL 必须可解析（safe_resolve_url 非 nil）
#   2. 有子项的顶级项必须含 ≥1 个「无条件可见或纯权限」的子项（常显原则）
#   3. 子项 `if:` 只接受权限判断；出现 count/size/state/业务状态 → 违规
#   4. 业务计数必须走 badge（禁止用业务条件隐藏菜单）
#   5. 特殊豁免：getting_started 的 `setup_completed?`（决策 2 保留）
#
# 违规时 exit 1（CI / pre-commit 阻断）。

# 业务关键字黑名单：出现在子项 `if:` 中即判定为「用业务状态隐藏菜单」
BUSINESS_CONDITION_KEYWORDS = /\b(count|size|state|status|positive\?|present\?|supported_locales|ready_to_ship|empty\?)\b/.freeze

# 纯权限判断的关键字白名单（允许出现在 `if:` 中）
PERMISSION_KEYWORDS = /\b(can\?|current_store|current_ability|authorize)\b/.freeze

namespace :pallastrade do
  namespace :admin do
    desc 'Validate admin navigation config against the nav schema (P5)'
    task nav_validate: :environment do
      violations = []
      warnings = []

      %i[sidebar settings].each do |context|
        nav = PallasTrade.admin.navigation.public_send(context)
        nav&.root_items&.each do |item|
          validate_item(item, context, violations, warnings)
        end
      end

      if violations.empty?
        puts "✅ nav:validate OK — #{warnings.size} warning(s)"
        warnings.each { |w| puts "⚠️  #{w}" }
      else
        puts "❌ nav:validate — #{violations.size} violation(s):"
        violations.each { |v| puts "   🚫 #{v}" }
        exit 1
      end
    end

    def validate_item(item, context, violations, warnings)
      path_prefix = "#{context}:#{item.key}"

      # ① 顶级项 icon 必填 + URL 可解析
      if item.parent_key.nil?
        if item.icon.blank? && !item.section?
          violations << "#{path_prefix}: 顶级导航项缺少 icon（Schema 要求顶级 icon 必填）"
        end
        if item.url.nil? && !item.section?
          violations << "#{path_prefix}: 顶级导航项缺少 url"
        elsif !item.section? && item.safe_resolve_url.nil?
          violations << "#{path_prefix}: 顶级导航项 URL 无法解析（#{item.url.inspect}）"
        end
      end

      # ② 有子项的顶级项必须含 ≥1 个无条件可见/纯权限子项（常显原则）
      if item.children.any?
        unconditionally_visible = item.children.any? { |child| child.condition.nil? }
        permission_only = item.children.any? { |child| permission_only_condition?(child.condition) }
        unless unconditionally_visible || permission_only
          violations << "#{path_prefix}: 所有子项都有业务条件 if: — 违反常显原则（须 ≥1 个无条件可见或纯权限子项）"
        end
      end

      # ③ 子项 if: 只接受权限判断（业务关键字 → 违规；getting_started 豁免）
      if item.condition && item.key != :getting_started
        if business_condition?(item.condition)
          violations << "#{path_prefix}: 子项/顶级项 `if:` 含业务状态关键字（count/size/state/...）— 业务计数须用 badge，菜单禁止因业务状态隐藏（豁免：getting_started setup_completed?）"
        end
      end

      item.children.each { |child| validate_item(child, context, violations, warnings) }
    end

    # 纯权限条件：probe 上下文执行只调用 can?/current_*，或无条件（nil）
    def permission_only_condition?(condition)
      return true if condition.nil?

      source = condition_source(condition)
      return true if source.nil? # 无法读取源码时保守放行（仅结构校验）

      # 纯权限：只出现 permission 关键字、不出现业务关键字
      !source.match?(BUSINESS_CONDITION_KEYWORDS) ||
        (source.match?(PERMISSION_KEYWORDS) && !source.match?(BUSINESS_CONDITION_KEYWORDS) && source.match?(/\bcan\?\b/))
    end

    def business_condition?(condition)
      source = condition_source(condition)
      return false if source.nil?

      source.match?(BUSINESS_CONDITION_KEYWORDS)
    end

    # 读取 Proc 源码（source_location → 该文件对应行），失败返回 nil
    def condition_source(condition)
      loc = condition.source_location
      return nil unless loc

      file, line = loc
      return nil unless file && File.exist?(file)

      source_line = File.readlines(file)[line - 1].to_s
      source_line.strip
    end
  end
end
