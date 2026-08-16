# frozen_string_literal: true

# PALLAS-CUSTOM: 管理后台导航 Schema 校验器（P5/P6 导航架构重构）
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
#   P6 新增：
#   6. 有子项的顶级项必须声明 `landing`，且 landing 指向存在的子项（顶级落地）
#   7. 声明 `tabs:` 的项必须指向已注册的 tab 上下文（如 :stock_tabs）
#   8. String 型 label（i18n key）必须 en + zh-CN 双语存在
#
# 违规时 exit 1（CI / pre-commit 阻断）。

# 业务关键字黑名单：出现在子项 `if:` 中即判定为「用业务状态隐藏菜单」
BUSINESS_CONDITION_KEYWORDS = /\b(count|size|state|status|positive\?|present\?|supported_locales|ready_to_ship|empty\?)\b/.freeze

# 纯权限判断的关键字白名单（允许出现在 `if:` 中）
PERMISSION_KEYWORDS = /\b(can\?|current_store|current_ability|authorize)\b/.freeze

# 双语必检的 locale（P6 FR-012：新增 label 双语 en/zh-CN）
I18N_LOCALES = %w[en zh-CN].freeze

namespace :pallastrade do
  namespace :admin do
    desc 'Validate admin navigation config against the nav schema (P5/P6)'
    task nav_validate: :environment do
      violations = []
      warnings = []

      # P6：主区/设置区统一为单一 sidebar 树；tab 上下文（tax_tabs 等）单独轻量校验
      nav = PallasTrade.admin.navigation.sidebar
      nav&.root_items&.each do |item|
        validate_item(item, :sidebar, violations, warnings)
      end

      %i[tax_tabs shipping_tabs team_tabs stock_tabs returns_tabs developers_tabs audit_tabs].each do |context|
        tab_nav = PallasTrade.admin.navigation.public_send(context)
        tab_nav&.root_items&.each do |item|
          validate_tab_item(item, context, violations, warnings)
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

        # ⑥ 有子项的顶级项必须声明 landing 且指向存在的子项（P6）
        if item.landing.nil?
          violations << "#{path_prefix}: 有子项的顶级项缺少 landing（P6 顶级落地 = 第一个子项，须显式声明）"
        else
          landing_child = item.children.find { |child| child.key == item.landing }
          if landing_child.nil?
            violations << "#{path_prefix}: landing 指向不存在的子项 :#{item.landing}"
          end
        end
      end

      # ⑦ tabs 声明必须指向已注册的 tab 上下文（P6）
      if item.tabs && !tab_context_registered?(item.tabs)
        violations << "#{path_prefix}: tabs 上下文 :#{item.tabs} 未注册（须在 engine.rb register_context）"
      end

      # ③ 子项 if: 只接受权限判断（业务关键字 → 违规；getting_started 豁免）
      if item.condition && item.key != :getting_started
        if business_condition?(item.condition)
          violations << "#{path_prefix}: 子项/顶级项 `if:` 含业务状态关键字（count/size/state/...）— 业务计数须用 badge，菜单禁止因业务状态隐藏（豁免：getting_started setup_completed?）"
        end
      end

      # ⑧ String 型 label（i18n key）必须 en + zh-CN 双语存在（P6 FR-012）
      validate_label_i18n(item, path_prefix, violations)

      item.children.each { |child| validate_item(child, context, violations, warnings) }
    end

    # 页面级 tab 上下文（tax_tabs 等）轻量校验：只查业务条件 + 双语，不要求 icon/landing
    def validate_tab_item(item, context, violations, warnings)
      path_prefix = "#{context}:#{item.key}"

      if item.condition && item.key != :getting_started
        if business_condition?(item.condition)
          violations << "#{path_prefix}: 子项/顶级项 `if:` 含业务状态关键字（count/size/state/...）— 业务计数须用 badge，菜单禁止因业务状态隐藏（豁免：getting_started setup_completed?）"
        end
      end

      validate_label_i18n(item, path_prefix, violations)

      item.children.each { |child| validate_tab_item(child, context, violations, warnings) }
    end

    # ⑧ 双语校验：String/Symbol label 若含 `.`（i18n key），en + zh-CN 都必须存在
    def validate_label_i18n(item, path_prefix, violations)
      label = item.label
      return unless label.is_a?(String) || label.is_a?(Symbol)

      key = label.to_s
      return unless key.include?('.')

      missing = I18N_LOCALES.reject do |locale|
        I18n.with_locale(locale) { I18n.exists?("pallastrade.#{key}", locale) }
      end
      return if missing.empty?

      violations << "#{path_prefix}: label #{key.inspect} 缺少 #{missing.join('/')} 翻译（FR-012 双语必填）"
    end

    def tab_context_registered?(name)
      PallasTrade.admin.navigation.context?(name)
    rescue StandardError
      false
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
