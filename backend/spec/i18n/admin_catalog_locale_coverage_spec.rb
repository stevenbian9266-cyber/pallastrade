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
  # products 是 2026-09-17 分批补齐的第一批；tables/variants_form/price_lists 是第二批；
  # 下面是第四批（30 个域，496 键）——**自建功能域优先**，因为它们每天都被商家用到，
  # 且翻译口径有权威依据（服务/模型语义），最不容易译错。
  DOMAINS = %w[
    catalog_health catalog_operations products.ai products
    tables variants_form price_lists
    duplicate_products bulk_ops product_history
    store_setup_tasks storefront_setup publishing dashboard
    webhook_endpoints webhook_deliveries api_keys oauth_applications webhooks_subscribers
    redirects channels imports markets checkout_settings store_form
    product_translations translations taxon_rules taxon_types option_types reviews
    promotion_categories gift_cards gift_card_batches posts
    table invitations
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
    imports tax_rates tax_categories shipping_methods shipping_categories
    return_authorization_reasons refund_reasons reimbursement_types
    stock_items stock_movements stock_transfers
    allowed_origins api_keys channels customer_groups customers developers
    draft_orders gift_cards home invitations markets metafield_definitions
    newsletter_subscribers options orders payments policies price_lists products
    promotions reports return_authorizations returns roles shipping stock
    stock_locations store_details tax translations users webhook_endpoints zones
    total_sales loading date_range_presets
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

  # 2026-09-17 第四批发现的**第二类**缺陷：键存在，但**位置错**。
  #
  # `Navigation::Item#resolve_label` 对 Symbol 标签走
  # `PallasTrade.t(label, default: label.to_s.humanize)`，而 `PallasTrade.t` 只前置
  # `:pallastrade` → 真实键路径是**顶层** `pallastrade.<key>`。
  # 这一批标签的中文此前被写在 `pallastrade.admin.<key>`，于是**永远读不到**，
  # 中文后台里走 humanize 兜底显示英文。
  #
  # 真渲染证据（/admin，locale=zh-CN）：修复前面包屑与页标题是 "Home"、侧栏是
  # "Orders" / "Draft orders"；修复后分别为「首页」「订单」「草稿订单」。
  #
  # 名单取自 `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb`
  # 里全部 `label: :<key>` 形式（48 个）。**新增 Symbol 标签时必须同步此表**，
  # 且中文必须落在顶层，不能写进 `admin.`。
  NAV_SYMBOL_LABELS = %w[
    allowed_origins api_keys blog channels customer_groups customers developers
    draft_orders emails exports gift_cards home imports invitations markets
    metafield_definitions newsletter_subscribers options orders payments policies
    price_lists products promotions redirects refund_reasons reimbursement_types
    reports return_authorization_reasons return_authorizations returns roles
    shipping shipping_categories shipping_methods stock stock_items stock_locations
    stock_movements stock_transfers store_details tax tax_categories tax_rates
    translations users webhook_endpoints zones
  ].freeze

  describe 'admin sidebar Symbol labels' do
    it 'resolves every Symbol label in zh-CN (no humanize fallback)' do
      missing = NAV_SYMBOL_LABELS.reject { |key| I18n.exists?("pallastrade.#{key}", :'zh-CN') }

      expect(missing).to be_empty, "这些导航标签会在中文后台显示英文: #{missing.inspect}"
    end

    it 'keeps them as plain labels, not shadowed by a feature-domain Hash' do
      # 反向保护：`pallastrade.imports` 这类标签即使存在，若被同名的功能域 Hash 覆盖，
      # 导航会直接把 Hash 渲染成标签（比显示英文更糟）。
      hashed = NAV_SYMBOL_LABELS.select do |key|
        I18n.t("pallastrade.#{key}", locale: :'zh-CN').is_a?(Hash)
      end

      expect(hashed).to be_empty, "导航标签被功能域 Hash 覆盖了: #{hashed.inspect}"
    end
  end

  # 全站**共享**标签组：它们不属于任何单个功能域，却会同时出现在多个页面上
  # （订单列表的状态徽章、各列表页的通用动作、购物车的优惠码报错、
  # 仪表盘的时间区间选择器）。因此单独做 en ↔ zh-CN 的**叶子**键集比对，
  # 而不是只断言组根存在（组根是 Hash，永远存在，断言它等于没测）。
  SHARED_TOP_LEVEL_GROUPS = %w[
    actions payment_states state_machine_states date_range_presets eligibility_errors
    shipment_states
  ].freeze

  describe 'shared top-level label groups' do
    SHARED_TOP_LEVEL_GROUPS.each do |group|
      it "has full zh-CN leaf coverage for pallastrade.#{group}" do
        en = flatten_keys(I18n.t("pallastrade.#{group}", locale: :en, default: {}))
        zh = flatten_keys(I18n.t("pallastrade.#{group}", locale: :'zh-CN', default: {}))
        missing = en - zh

        expect(missing).to be_empty, "pallastrade.#{group} 缺中文: #{missing.inspect}"
      end
    end
  end

  # —— 全局保证（2026-09-17 最终批）——
  #
  # 逐域断言会随着域增长而不断追加；全局断言给出的是**总体保证**：
  # en 侧 `pallastrade.*` 的每一个叶子键，zh-CN 侧都必须有值。
  # CI 是干净检出，所以它等价于「中文后台不会出现英文/translation missing」。
  #
  # IN_FLIGHT_PREFIXES：**并行会话尚未提交**的 en 键。它们的 en 定义还不在 HEAD 里，
  # 现在就补 zh 会让这些键在干净检出上变成孤儿（CI 红），故先从断言中排除。
  # 对应批次提交后，把条目从这里删掉并补上中文即可。
  IN_FLIGHT_PREFIXES = %w[
    pallastrade.three_d_secure
    pallastrade.admin.payment_methods.payment_option_three_d_secure
  ].freeze

  describe '上架即中文：en 有的 zh-CN 必须有（全局）' do
    it 'has a zh-CN value for every en pallastrade leaf' do
      en = flatten_keys(I18n.t('pallastrade', locale: :en, default: {}))
      missing = en.reject do |key|
        full = "pallastrade.#{key}"
        IN_FLIGHT_PREFIXES.any? { |prefix| full.start_with?(prefix) } ||
          I18n.exists?(full, :'zh-CN')
      end

      expect(missing).to be_empty,
                         "中文后台会显示英文或 translation missing: #{missing.first(25).inspect}（共 #{missing.size} 个）"
    end

    # 第三类缺陷：**同一路径上 zh 是字符串、en 是 Hash**（或反之）时，
    # i18n 深合并会让后加载的一方把另一方整个覆盖，且不报错、不 warning。
    # 本仓真实案例：`pallastrade.admin.imports` 在 en 侧是导入向导的功能域 Hash，
    # zh 侧曾是导航标签字符串「导入」——两边互相挤。
    it 'never lets a zh-CN leaf shadow an en Hash at the same path' do
      zh = flatten_keys(I18n.t('pallastrade', locale: :'zh-CN', default: {}))
      colliding = zh.select do |key|
        I18n.t("pallastrade.#{key}", locale: :en, default: nil).is_a?(Hash)
      end

      expect(colliding).to be_empty,
                           "这些 zh 键与 en 的功能域 Hash 同址，会互相覆盖: #{colliding.inspect}"
    end
  end

  # 第三个命名空间：`activerecord.attributes.<model>.<attr>`（表单字段的默认标签）。
  # 缺失时中文后台显示 `Translation missing: zh-CN.activerecord.attributes.…`。
  #
  # 这里是**实测渲染到的**那一小撮（en 侧该命名空间有 1231 键，绝大多数永不渲染，
  # 因为各表单都用显式的 `PallasTrade.t('admin.…')` 标签）。新增表单后若再出现
  # translation missing，把新键追加到这里即可。
  AR_ATTRIBUTES = %w[
    pallastrade/address.address1 pallastrade/address.address2
    pallastrade/address.city pallastrade/address.company pallastrade/address.phone
    pallastrade/metafield_definition.namespace
    pallastrade/import.preferred_delimiter
    pallastrade/store.preferred_limit_digital_download_days
    pallastrade/store.preferred_limit_digital_download_count
    pallastrade/store.preferred_digital_asset_authorized_days
    pallastrade/store.preferred_digital_asset_authorized_clicks
  ].freeze

  describe 'activerecord.attributes（表单字段默认标签）' do
    it 'resolves every rendered attribute name in zh-CN' do
      missing = AR_ATTRIBUTES.reject do |key|
        I18n.exists?("activerecord.attributes.#{key}", :'zh-CN')
      end

      expect(missing).to be_empty, "中文后台会显示 Translation missing: #{missing.inspect}"
    end

    it 'never renders a translation-missing attribute label' do
      values = AR_ATTRIBUTES.map do |key|
        I18n.t("activerecord.attributes.#{key}", locale: :'zh-CN', default: nil)
      end

      expect(values).to all(be_a(String))
      expect(values.grep(/translation missing/i)).to be_empty
    end
  end
end
