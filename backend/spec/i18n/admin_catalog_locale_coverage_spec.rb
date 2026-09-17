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
  # products.ai 是 2026-09-16 实测发现的：缺它会让 AI 按钮的 title 属性被 HTML 撕开。
  # products 是 2026-09-17 分批补齐的第一批；下面三个是第二批
  # （量化与策略见 docs/research/RESEARCH-20260917-admin-i18n-gap.md）。
  DOMAINS = %w[
    catalog_health catalog_operations products.ai products
    tables variants_form price_lists
  ].freeze

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
        # 注意：keys_for 返回的是**相对** domain 的路径（`stock`，不是 `products.stock`）。
        #
        # 导航子项的中文键落在 admin.products.<nav_item>，而 en 侧对应键在别处
        # （导航标签由 admin_nav.en.yml 提供）—— 这类是**既有**的、无害的孤儿：
        # 孤儿键不会导致 translation missing，只是键位卫生问题。
        # 这里只排除这四个已知项，新出现的孤儿仍会被抓。
        known_preexisting = %w[stock translations options price_lists]
        orphan = keys_for(:'zh-CN', domain) - keys_for(:en, domain) - known_preexisting

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

  # 第三个来源：**顶级** `pallastrade.<key>`（视图用 `PallasTrade.t(:in_stock)` 这类写法，
  # 没有 `admin.` 前缀）。量化显示总缺 1234 键，其中 415 个不在 admin.* 下 —— 上面的
  # DOMAINS 结构检查不到它们，所以这里单独守一批（第三批补的高频顶级键）。
  TOP_LEVEL_BATCH = %w[
    redirects emails variant blog profile exports webhook_deliveries
    add_action_of_type add_coupon_code add_gift_card add_new_address add_one
    add_option_value add_rule_of_type add_selected add_selected_products
    add_selected_variant add_variant added_at
    adjustment_amount_help adjustment_closed_description adjustment_open_description
    all_items_have_been_returned all_time applied_to calculated_reimbursements
    alt_text assigned_variants assigned_variants_help
    are_you_sure_delete authorization_failure automatic_promotion breadcrumbs
    cancel_order cannot_perform_operation
    in_stock variants
  ].freeze

  # 回归：商品列表库存列曾长期渲染 `translation missing:
  # zh-cn.pallastrade.in_stock`。
  # 服务端 I18n.locale 一直是 `:"zh-CN"`（大写，正确），小写的 `zh-cn`
  # 是 i18n 在 fallback 解析时另一次查表的结果 —— 即这两个键在 zh-CN
  # 下确实缺失，不是 locale 被写坏了。此处把结论钉死：
  # 1) 两个键必须在 zh-CN 下可解析（否则回退链会再次报 missing）；
  # 2) 键名必须是小写无前缀的顶级键（helper 里就是这么调的）。
  describe '商品列表库存列（已修缺陷回归）' do
    %w[in_stock variants].each do |key|
      it "resolves pallastrade.#{key} in zh-CN" do
        expect(I18n.exists?("pallastrade.#{key}", :'zh-CN')).to be(true)
      end
    end

    it 'renders the inventory cell without a missing-translation marker' do
      # `display_inventory` 拼的是 "<qty> <in_stock> - <n> <variants>"，
      # 且对两个标签调用过 `.downcase`；中文不受 downcase 影响。
      cell = "15000 #{I18n.t('pallastrade.in_stock', locale: :'zh-CN')} - 3 " \
             "#{I18n.t('pallastrade.variants', locale: :'zh-CN')}"
      expect(cell).not_to include('translation missing')
      expect(cell).not_to include('zh-cn.')
      expect(cell).to eq('15000 有货 - 3 变体')
    end
  end

  describe 'top-level pallastrade keys' do
    TOP_LEVEL_BATCH.each do |key|
      it "has a zh-CN value for pallastrade.#{key}" do
        expect(I18n.exists?("pallastrade.#{key}", :'zh-CN')).to be(true),
                           "pallastrade.#{key} 缺中文（含 admin. 前缀的检查覆盖不到顶级键）"
      end
    end

    it 'never leaves a top-level key rendering as en in the Chinese admin' do
      missing = TOP_LEVEL_BATCH.reject { |key| I18n.exists?("pallastrade.#{key}", :'zh-CN') }

      expect(missing).to be_empty
    end
  end
end
