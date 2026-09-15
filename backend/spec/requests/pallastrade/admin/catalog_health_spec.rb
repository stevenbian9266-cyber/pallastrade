# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-admin-catalog-health-v1 —— 管理后台 Catalog Health V1
#（商品健康待办中心 + 一键过滤列表）
#
#   AC-001 ← FR-001：待办中心渲染 7 行 issue
#   AC-002 ← FR-005：missing_media（产品层与变体层都无资产才算）
#   AC-003 ← FR-005：missing_description / missing_seo（默认 locale 有效值）
#   AC-004 ← FR-005：active_zero_stock（预售/可缺货/不追踪/有库存均不计）
#   AC-005 ← FR-005：old_drafts（draft 且 30 天未更新）
#   AC-006 ← FR-003：missing_translations（产品 × 语言 缺失对数；单语言恒 0）
#   AC-007 ← FR-004：redirect_unresolved（未建 301 的 URL 变更）
#   AC-008 ← FR-002：?health_issue= 过滤（计数 == 列表条数；非法 key 忽略）
#   AC-009 ← FR-006：筛选态横幅（含清除链接；未筛选不渲染）
#   AC-010 ← FR-007：导航项 + Product 读权限守卫
#   AC-011 ← FR-001/FR-006：i18n 键齐备（经 PallasTrade.t 断言）
RSpec.describe 'Admin catalog health', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "catalog_health_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en',
                   supported_locales: 'de,fr', name: 'Health Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def issue_count(key)
    PallasTrade::CatalogHealth::Issues.count(store, key)
  end

  def issue_list(key)
    PallasTrade::CatalogHealth::Issues.product_relation(store.products, key, store: store)
  end

  # 默认语言（en）没有描述的“问题商品”：清掉工厂给的描述（列 + 翻译行双保险）
  def product_missing_description(name)
    product = create(:product, store: store, name: name, description: nil)
    product.translations.where(locale: 'en').update_all(description: nil)
    product.update_columns(description: nil)
    product
  end

  describe 'AC-001 待办中心页' do
    it 'renders all seven issues with their drill-down targets (AC-001)' do
      stale = product_missing_description('Stale Product')
      stale.update_columns(status: 'draft', updated_at: 40.days.ago,
                           meta_title: nil, meta_description: nil)

      live = create(:product, store: store, name: 'Live Zero Stock')
      live.master.stock_items.update_all(count_on_hand: 0, backorderable: false)
      live.update_columns(status: 'active')
      live.translations.where(locale: 'en').update_all(meta_title: nil, meta_description: nil)

      changed = create(:product, store: store, name: 'Url Changed Product')
      changed.update!(slug: 'url-changed-product-new')

      sign_in_as_admin
      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      PallasTrade::CatalogHealth::Issues::KEYS.each do |key|
        expect(issue_count(key)).to be_positive, "fixture missing for #{key}"
        expect(response.body).to include(PallasTrade.t("admin.catalog_health.issues.#{key}"))
      end

      # 5 类商品级 issue → 过滤后的商品列表；2 类 → 既有专页
      PallasTrade::CatalogHealth::Issues::PRODUCT_FILTER_KEYS.each do |key|
        expect(response.body).to include("health_issue=#{key}")
      end
      expect(response.body).to include(PallasTrade.admin_product_translations_path)
      expect(response.body).to include(PallasTrade.admin_redirects_path)
    end
  end

  describe 'AC-002 missing_media' do
    it 'counts products whose variants have no assets either (AC-002)' do
      bare = create(:product, store: store, name: 'Bare Product')
      variant_image = create(:product, store: store, name: 'Variant Image Product')
      create(:image, viewable: variant_image.master)
      product_image = create(:product, store: store, name: 'Product Image Product')
      create(:image, viewable: product_image)

      list = issue_list('missing_media')
      expect(list).to include(bare)
      expect(list).not_to include(variant_image, product_image)
      expect(issue_count('missing_media')).to eq(1)
    end
  end

  describe 'AC-003 missing_description / missing_seo' do
    it 'reads the effective default-locale value (translation row first, column fallback) (AC-003)' do
      missing = product_missing_description('No Description')
      from_column = create(:product, store: store, name: 'From Column', description: nil)
      from_column.translations.where(locale: 'en').delete_all
      from_column.update_columns(description: 'Column fallback')

      expect(issue_list('missing_description')).to eq([missing])
    end

    it 'flags a product when either meta field is missing (AC-003)' do
      complete = create(:product, store: store, name: 'Seo Complete')
      complete.update!(meta_title: 'Title', meta_description: 'Description')
      partial = create(:product, store: store, name: 'Seo Partial')
      partial.update!(meta_title: 'Title Only')
      partial.translations.where(locale: 'en').update_all(meta_description: nil)
      partial.update_columns(meta_description: nil)

      list = issue_list('missing_seo')
      expect(list).to include(partial)
      expect(list).not_to include(complete)
    end
  end

  describe 'AC-004 active_zero_stock' do
    it 'counts only active products with nothing sellable (AC-004)' do
      zero_stock = create(:product, store: store, name: 'Zero Stock')
      zero_stock.master.stock_items.update_all(count_on_hand: 0, backorderable: false)
      zero_stock.update_columns(status: 'active')

      in_stock = create(:product, store: store, name: 'In Stock')
      in_stock.master.stock_items.update_all(count_on_hand: 5, backorderable: false)
      in_stock.update_columns(status: 'active')

      backorderable = create(:product, store: store, name: 'Backorderable')
      backorderable.master.stock_items.update_all(count_on_hand: 0, backorderable: true)
      backorderable.update_columns(status: 'active')

      preorder = create(:product, store: store, name: 'Preorderable')
      preorder.master.stock_items.update_all(count_on_hand: 0, backorderable: false)
      preorder.master.update_columns(preorderable: true)
      preorder.update_columns(status: 'active')

      untracked = create(:product, store: store, name: 'Untracked')
      untracked.master.stock_items.update_all(count_on_hand: 0, backorderable: false)
      untracked.master.update_columns(track_inventory: false)
      untracked.update_columns(status: 'active')

      draft_zero = create(:product, store: store, name: 'Draft Zero')
      draft_zero.master.stock_items.update_all(count_on_hand: 0, backorderable: false)
      draft_zero.update_columns(status: 'draft')

      expect(issue_list('active_zero_stock')).to eq([zero_stock])
    end
  end
  describe 'AC-005 old_drafts' do
    it 'counts drafts untouched for 30+ days only (AC-005)' do
      old_draft = create(:product, store: store, name: 'Old Draft')
      old_draft.update_columns(status: 'draft', updated_at: 40.days.ago)

      fresh_draft = create(:product, store: store, name: 'Fresh Draft')
      fresh_draft.update_columns(status: 'draft', updated_at: 2.days.ago)

      old_active = create(:product, store: store, name: 'Old Active')
      old_active.update_columns(status: 'active', updated_at: 40.days.ago)

      expect(issue_list('old_drafts')).to eq([old_draft])
    end
  end

  describe 'AC-006 missing_translations' do
    it 'counts product × locale pairs missing a translated name (AC-006)' do
      first = create(:product, store: store, name: 'First')
      second = create(:product, store: store, name: 'Second')
      first.translations.create!(locale: 'de', name: 'Erste')

      # 2 个商品 × 2 个非默认语言（de/fr）− 1 个已翻译 = 3
      expect(issue_count('missing_translations')).to eq(3)
      expect(second).to be_present
    end

    it 'is zero for a single-locale store (AC-006)' do
      other_store = create(:store, code: "catalog_health_single_#{SecureRandom.hex(4)}",
                                    default_locale: 'en', supported_locales: nil)
      create(:product, store: other_store, name: 'Single Locale Product')

      expect(PallasTrade::CatalogHealth::Issues.count(other_store, 'missing_translations')).to eq(0)
    end
  end

  describe 'AC-007 redirect_unresolved' do
    it 'counts URL changes without a 301 and drops them once handled (AC-007)' do
      product = create(:product, store: store, name: 'Old Shaver')
      product.update!(slug: 'new-shaver')
      expect(issue_count('redirect_unresolved')).to eq(1)

      create(:redirect, store: store, from_path: '/products/old-shaver', to_path: '/products/new-shaver')
      expect(issue_count('redirect_unresolved')).to eq(0)
    end
  end

  describe 'AC-008 过滤列表' do
    it 'filters the products list by the same scope it counted with (AC-008)' do
      create(:product, store: store, name: 'NoImage Alpha')
      with_image = create(:product, store: store, name: 'HasImage Beta')
      create(:image, viewable: with_image)

      sign_in_as_admin
      get '/admin/products', params: { health_issue: 'missing_media' }

      expect(response).to have_http_status(:ok)
      expect(issue_count('missing_media')).to eq(1)
      expect(response.body).to include('NoImage Alpha')
      expect(response.body).not_to include('HasImage Beta')
    end

    it 'ignores an unknown health_issue key (AC-008)' do
      create(:product, store: store, name: 'Plain Product')
      sign_in_as_admin

      get '/admin/products', params: { health_issue: 'not_a_real_issue' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Plain Product')
      expect(response.body).not_to include(PallasTrade.t('admin.catalog_health.filter.active'))
    end
  end

  describe 'AC-009 筛选态横幅' do
    it 'renders the banner with a clear link while filtered, nothing otherwise (AC-009)' do
      create(:product, store: store, name: 'Banner Product')
      sign_in_as_admin

      get '/admin/products', params: { health_issue: 'old_drafts' }
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.filter.active'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.issues.old_drafts'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.filter.clear'))

      get '/admin/products'
      expect(response.body).not_to include(PallasTrade.t('admin.catalog_health.filter.active'))
    end
  end

  describe 'AC-010 导航与权限' do
    it 'registers the navigation entry under Products (AC-010)' do
      products = PallasTrade.admin.navigation.sidebar.find(:products)
      entry = products.children.find { |child| child.key == :catalog_health }

      expect(entry).not_to be_nil
      expect(entry.label).to eq('admin.catalog_health.title')
      expect(entry.url).to eq(:admin_catalog_health_path)
    end

    it 'serves the page to product readers (AC-010)' do
      sign_in_as_admin
      get '/admin/catalog_health'
      expect(response).to have_http_status(:ok)
    end

    it 'denies access when the ability cannot read products (AC-010)' do
      sign_in_as_admin

      denying_ability = Class.new do
        def authorize!(*)
          raise CanCan::AccessDenied
        end

        def can?(*)
          false
        end
      end.new

      allow_any_instance_of(PallasTrade::Admin::CatalogHealthController)
        .to receive(:current_ability).and_return(denying_ability)

      get '/admin/catalog_health', headers: { 'HTTP_REFERER' => '/admin/products' }

      expect(response).to have_http_status(:found)
    end
  end

  describe 'AC-011 i18n' do
    it 'ships every catalog health label (AC-011)' do
      keys = PallasTrade::CatalogHealth::Issues::KEYS.flat_map do |key|
        ["admin.catalog_health.issues.#{key}", "admin.catalog_health.hints.#{key}"]
      end
      keys += %w[
        admin.catalog_health.title
        admin.catalog_health.intro
        admin.catalog_health.issues_heading
        admin.catalog_health.issue
        admin.catalog_health.count
        admin.catalog_health.action
        admin.catalog_health.view
        admin.catalog_health.filter.active
        admin.catalog_health.filter.clear
      ]

      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing i18n key #{key}"
      end
    end
  end

  describe '降级' do
    it 'keeps the page 200 when a single counter blows up (AC-001 / NFR)' do
      sign_in_as_admin
      allow(PallasTrade::CatalogHealth::Issues).to receive(:count).and_wrap_original do |original, target_store, key|
        raise StandardError, 'boom' if key.to_s == 'missing_media'

        original.call(target_store, key)
      end

      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.issues.missing_media'))
    end
  end
end
