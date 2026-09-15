# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-d2-duplicate-detection —— 重复商品检测
#（标签/ SKU / 名称三类信号候选发现 + 对比视图，只读）
#
#   AC-001 ← FR-002：同名商品（规范化后相同）→ duplicate_name 组
#   AC-002 ← FR-002：名称仅大小写/首尾空格不同 → 仍视为同名
#   AC-003 ← FR-002：变体共用条码 → duplicate_barcode 组；空条码不分组
#   AC-004 ← FR-002：变体共用 SKU（大小写不同）→ duplicate_sku 组
#   AC-005 ← FR-003：每个信号的计数 == 该信号候选组数（概览与列表同源）
#   AC-006 ← FR-002/FR-007：archived / 已删除商品、已删除变体、其他店铺不出现
#   AC-007 ← FR-004：工作台页渲染三类信号与候选行
#   AC-008 ← FR-004：?signal= 过滤；非法 signal 忽略（回全量）
#   AC-009 ← FR-005：对比页并排字段 + 缺失值占位
#   AC-010 ← FR-006：导航子项 + 读权限守卫
#   AC-011 ← FR-008：i18n 键齐备（经 PallasTrade.t 断言）
#   AC-012 ← FR-004：无候选时空态
RSpec.describe 'Admin duplicate products', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "duplicate_products_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'Duplicate Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def candidate_groups(signal: nil)
    PallasTrade::Products::DuplicateCandidates.call(store, signal: signal)
  end

  # SKU / 条码唯一性校验会拦下「故意重复」的赋值，所以夹具直写列（这正是线上
  # 重复数据能存在的原因：校验可关闭/可绕过，条码则完全没有校验）。
  def set_master(product, sku: nil, barcode: nil)
    attributes = {}
    attributes[:sku] = sku if sku
    attributes[:barcode] = barcode
    product.master.update_columns(attributes)
  end

  def other_store
    @other_store ||= create(:store, code: "duplicate_other_#{SecureRandom.hex(4)}",
                                   default_currency: 'USD', default_locale: 'en')
  end

  it 'AC-001/AC-002: groups products whose names match ignoring case and surrounding spaces' do
    first = create(:product, store: store, name: 'Blue Blender')
    second = create(:product, store: store, name: 'blue blender ')

    group = candidate_groups(signal: 'duplicate_name').find { |candidate| candidate.key == 'blue blender' }

    expect(group).to be_present
    expect(group.products.map(&:id)).to match_array([first.id, second.id])
    expect(group.total_count).to eq(2)
  end

  it 'AC-003: groups variants sharing a barcode and never groups the blank ones' do
    first = create(:product, store: store, name: 'Barcode One')
    second = create(:product, store: store, name: 'Barcode Two')
    blank = create(:product, store: store, name: 'Barcode Blank')
    set_master(first, barcode: 'BAR-123')
    set_master(second, barcode: 'bar-123')
    set_master(blank, barcode: nil)

    groups = candidate_groups(signal: 'duplicate_barcode')
    group = groups.find { |candidate| candidate.key == 'bar-123' }

    expect(groups.map(&:signal).uniq).to eq(['duplicate_barcode'])
    expect(group.products.map(&:id)).to match_array([first.id, second.id])
    expect(group.products).not_to include(blank)
  end

  it 'AC-004: groups variants sharing a SKU regardless of case' do
    first = create(:product, store: store, name: 'SKU One')
    second = create(:product, store: store, name: 'SKU Two')
    set_master(first, sku: 'SKU-ABC')
    set_master(second, sku: 'sku-abc')

    group = candidate_groups(signal: 'duplicate_sku').find { |candidate| candidate.key == 'sku-abc' }

    expect(group).to be_present
    expect(group.products.map(&:id)).to match_array([first.id, second.id])
  end

  it 'AC-005: per-signal counts equal the groups the page lists' do
    first = create(:product, store: store, name: 'Count SKU A')
    second = create(:product, store: store, name: 'Count SKU B')
    set_master(first, sku: 'CNT-1', barcode: 'CNT-BAR')
    set_master(second, sku: 'cnt-1', barcode: 'cnt-bar')
    create(:product, store: store, name: 'Count Name')
    create(:product, store: store, name: 'count name')

    sign_in_as_admin
    get '/admin/duplicate_products'

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('data-testid="duplicate-candidate"').size).to eq(3)

    PallasTrade::Products::DuplicateCandidates::SIGNALS.each do |signal|
      expected = candidate_groups(signal: signal).size
      expect(PallasTrade::Products::DuplicateCandidates.counts(store)[signal]).to eq(expected)
      expect(response.body.scan(%(data-testid="duplicate-candidate" data-signal="#{signal}")).size).to eq(expected)
    end
  end

  it 'AC-006: keeps archived, deleted and cross-store products out of a name group' do
    create(:product, store: store, name: 'Shared Name')
    archived = create(:product, store: store, name: 'Shared Name')
    archived.update_columns(status: 'archived')
    deleted = create(:product, store: store, name: 'Shared Name')
    deleted.update_columns(deleted_at: Time.current)
    create(:product, store: other_store, name: 'Shared Name')

    expect(candidate_groups(signal: 'duplicate_name')).to be_empty
  end

  it 'AC-006: keeps deleted variants and other stores out of a barcode group' do
    live = create(:product, store: store, name: 'Barcode Live')
    deleted = create(:product, store: store, name: 'Barcode Deleted')
    cross_store = create(:product, store: other_store, name: 'Barcode Other')
    set_master(live, barcode: 'SHARED-BAR')
    set_master(deleted, barcode: 'SHARED-BAR')
    deleted.master.update_columns(deleted_at: Time.current)
    set_master(cross_store, barcode: 'SHARED-BAR')

    expect(candidate_groups(signal: 'duplicate_barcode')).to be_empty
  end

  it 'AC-007: renders the signal overview and the candidate rows' do
    first = create(:product, store: store, name: 'Render Alpha')
    second = create(:product, store: store, name: 'Render Beta')
    set_master(first, sku: 'REN-1')
    set_master(second, sku: 'ren-1')

    sign_in_as_admin
    get '/admin/duplicate_products'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.title'))
    PallasTrade::Products::DuplicateCandidates::SIGNALS.each do |signal|
      expect(response.body).to include(PallasTrade.t("admin.duplicate_products.signals.#{signal}"))
    end
    expect(response.body).to include('ren-1')
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.compare'))
    expect(response.body.scan('data-testid="duplicate-candidate"').size).to eq(1)
  end

  it 'AC-008: filters by signal and ignores an unknown one' do
    first = create(:product, store: store, name: 'Filter SKU A')
    second = create(:product, store: store, name: 'Filter SKU B')
    set_master(first, sku: 'FIL-1')
    set_master(second, sku: 'FIL-1')
    create(:product, store: store, name: 'Filter Name')
    create(:product, store: store, name: 'filter name')

    sign_in_as_admin
    get '/admin/duplicate_products', params: { signal: 'duplicate_name' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.filter.active'))
    expect(response.body.scan('data-testid="duplicate-candidate"').size).to eq(1)
    expect(response.body.scan('data-testid="duplicate-candidate" data-signal="duplicate_name"').size).to eq(1)

    get '/admin/duplicate_products', params: { signal: 'not-a-signal' }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(PallasTrade.t('admin.duplicate_products.filter.active'))
    expect(response.body.scan('data-testid="duplicate-candidate"').size).to eq(2)
  end

  it 'AC-009: compares the selected products side by side with a placeholder for blanks' do
    first = create(:product, store: store, name: 'Compare Alpha')
    second = create(:product, store: store, name: 'Compare Beta')
    set_master(first, sku: 'CMP-SKU-1', barcode: 'CMP-BAR-1')

    sign_in_as_admin
    get '/admin/duplicate_products/compare', params: { product_ids: [first.id, second.id] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.compare_title'))
    expect(response.body).to include(first.name)
    expect(response.body).to include(second.name)
    expect(response.body).to include('CMP-SKU-1')
    expect(response.body).to include('CMP-BAR-1')
    expect(response.body).to include('data-attribute="barcodes"')
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.blank_value'))
  end

  it 'AC-012: renders the empty state when nothing looks duplicated' do
    create(:product, store: store, name: 'Unique Blender')

    sign_in_as_admin
    get '/admin/duplicate_products'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.duplicate_products.empty'))
  end

  describe 'AC-010 navigation and permissions' do
    it 'registers the entry right after Catalog Health' do
      products = PallasTrade.admin.navigation.sidebar.find(:products)
      entry = products.children.find { |child| child.key == :duplicate_products }

      expect(entry).not_to be_nil
      expect(entry.label).to eq('admin.duplicate_products.title')
      expect(entry.url).to eq(:admin_duplicate_products_path)
    end

    it 'serves the page to product readers' do
      sign_in_as_admin
      get '/admin/duplicate_products'
      expect(response).to have_http_status(:ok)
    end

    it 'denies access when the ability cannot read products' do
      sign_in_as_admin

      denying_ability = Class.new do
        def authorize!(*)
          raise CanCan::AccessDenied
        end

        def can?(*)
          false
        end
      end.new

      allow_any_instance_of(PallasTrade::Admin::DuplicateProductsController)
        .to receive(:current_ability).and_return(denying_ability)

      get '/admin/duplicate_products', headers: { 'HTTP_REFERER' => '/admin/products' }

      expect(response).to have_http_status(:found)
    end
  end

  describe 'AC-011 i18n' do
    it 'ships every duplicate products label' do
      keys = PallasTrade::Products::DuplicateCandidates::SIGNALS.flat_map do |signal|
        ["admin.duplicate_products.signals.#{signal}", "admin.duplicate_products.hints.#{signal}"]
      end
      keys += %w[name slug status variants barcodes price stock channels categories created_at updated_at]
              .map { |attribute| "admin.duplicate_products.attributes.#{attribute}" }
      keys += %w[active archived draft paused].map { |status| "admin.duplicate_products.statuses.#{status}" }
      keys += %w[
        admin.duplicate_products.title
        admin.duplicate_products.intro
        admin.duplicate_products.signals_heading
        admin.duplicate_products.signal
        admin.duplicate_products.count
        admin.duplicate_products.action
        admin.duplicate_products.view
        admin.duplicate_products.shared_value
        admin.duplicate_products.products
        admin.duplicate_products.candidates_heading
        admin.duplicate_products.empty
        admin.duplicate_products.more
        admin.duplicate_products.compare
        admin.duplicate_products.compare_title
        admin.duplicate_products.compare_intro
        admin.duplicate_products.compare_empty
        admin.duplicate_products.attribute
        admin.duplicate_products.blank_value
        admin.duplicate_products.filter.active
        admin.duplicate_products.filter.clear
      ]

      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing i18n key #{key}"
      end
    end
  end
end
