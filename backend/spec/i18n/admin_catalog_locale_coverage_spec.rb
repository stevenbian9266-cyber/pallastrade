# frozen_string_literal: true

require 'rails_helper'

# 宿主 zh-CN 覆盖契约（2026-09-16）
#
# 为什么需要这条测试：admin 的 UI 语言取自 `current_store.preferred_admin_locale`，
# 而 gem 只提供 en 文案。**只加 en 不会让任何测试变红** —— 中文门店的后台只会静默地
# 整页显示 `Translation missing: zh-CN.admin.xxx`，CI 与 spec 全绿。本批就是这么漏掉
# catalog_health / catalog_operations 的（catalog_health 连既有的 7 类 issue 都一直是缺的）。
#
# 因此这里对**已交付的**域名做双向断言：
#   1. en 侧存在的键，zh-CN 侧必须存在（不得静默回落）；
#   2. 两边的**键集完全一致**（多出一个孤儿中文键同样是缺陷）。
RSpec.describe 'Admin zh-CN locale coverage' do
  # 键集与 gem `pallastrade_admin/config/locales/en.yml` 的 admin.<domain> 一一对应。
  DOMAINS = %w[catalog_health catalog_operations].freeze

  def keys_for(locale, domain)
    tree = I18n.t("pallastrade.admin.#{domain}", locale: locale, default: {})
    raise "missing pallastrade.admin.#{domain} for #{locale}" unless tree.is_a?(Hash)

    flatten_keys(tree)
  end

  def flatten_keys(node, prefix = nil)
    node.flat_map do |key, value|
      path = [prefix, key].compact.join('.')
      value.is_a?(Hash) ? flatten_keys(value, path) : path
    end.sort
  end

  DOMAINS.each do |domain|
    describe "pallastrade.admin.#{domain}" do
      it 'has a zh-CN translation for every en key' do
        missing = keys_for(:en, domain) - keys_for(:'zh-CN', domain)

        expect(missing).to be_empty,
                           "#{domain} 缺少 zh-CN 文案（中文后台会显示 Translation missing）: #{missing.inspect}"
      end

      it 'has no orphan zh-CN keys that en does not define' do
        orphan = keys_for(:'zh-CN', domain) - keys_for(:en, domain)

        expect(orphan).to be_empty, "#{domain} 有 en 侧不存在的孤儿键: #{orphan.inspect}"
      end

      it 'never renders a translation-missing string in zh-CN' do
        tree = I18n.t("pallastrade.admin.#{domain}", locale: :'zh-CN', default: {})
        leaves = flatten_values(tree)

        expect(leaves.grep(/translation missing/i)).to be_empty
      end

      def flatten_values(node)
        node.flat_map { |_key, value| value.is_a?(Hash) ? flatten_values(value) : value.to_s }
      end
    end
  end

  # 界面实际取用的四个新键（G-7 趋势列）—— 存在性 + 中文可读性
  it 'renders the G-7 trend column labels in zh-CN' do
    {
      'pallastrade.admin.catalog_health.trend.heading' => '趋势',
      'pallastrade.admin.catalog_health.trend.unknown' => '暂无趋势',
      'pallastrade.admin.catalog_health.trend.directions.improving' => '改善',
      'pallastrade.admin.catalog_health.trend.directions.worsening' => '恶化'
    }.each do |key, expected|
      expect(I18n.t(key, locale: :'zh-CN')).to eq(expected)
    end
  end
end
