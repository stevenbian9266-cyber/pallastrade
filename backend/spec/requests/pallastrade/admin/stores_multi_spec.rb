# frozen_string_literal: true

require 'rails_helper'

# PRD-20260817-admin-多店铺管理-店铺列表-新建-切换
# AC-001 列表 / AC-002 新建+授权+切换 / AC-003 校验 / AC-004 切换器+授权
# AC-005 权限门控 / AC-006 单店铺兼容 / AC-007 编辑回归
RSpec.describe 'Admin multi-store management', type: :request do
  let!(:store_a) { create(:store, code: 'multi_store_a', name: 'Store A', url: 'a.example.com', default: true) }
  let!(:store_b) { create(:store, code: 'multi_store_b', name: 'Store B', url: 'b.example.com') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store_a, store: store_a)
  end

  def create_staff_user(store)
    staff = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    staff_role = create(:role, name: "staff_#{SecureRandom.hex(4)}")
    PallasTrade::RolePermission.create!(role: staff_role, permission_type: 'function', resource: 'orders', action: 'read')
    create(:role_user, user: staff, role: staff_role, resource: store, store: store)
    staff
  end

  # PRD-... AC-001
  it 'lists all stores with default badge' do
    sign_in_as_superuser
    get '/admin/stores'
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('Store A')
    expect(body).to include('Store B')
    expect(body).to include(PallasTrade.t(:default))
    # bug 2026-08-17：Switch 链接必须用 turbo_method（Turbo 约定），否则点击变 GET 404 空白页
    expect(body).to include('data-turbo-method="post"')
    expect(body).not_to include('data-method="post"')
  end

  # bugfix 2026-08-17：stores_controller skip_breadcrumb_derivation=true，列表/新建需手写面包屑
  it 'renders breadcrumbs on the stores list and new pages' do
    sign_in_as_superuser
    get '/admin/stores'
    list_crumb = Nokogiri::HTML(response.body).at_css('nav[aria-label="breadcrumb"]')&.text.to_s
    expect(list_crumb).to include(PallasTrade.t('admin.stores.title'))

    get '/admin/stores/new'
    new_crumb = Nokogiri::HTML(response.body).at_css('nav[aria-label="breadcrumb"]')&.text.to_s
    expect(new_crumb).to include(PallasTrade.t('admin.stores.title'))
    expect(new_crumb).to include(PallasTrade.t('admin.stores.new_title'))
  end

  # PRD-... AC-002
  it 'creates a store, grants the creator admin role and auto-switches to it' do
    sign_in_as_superuser
    expect {
      post '/admin/stores', params: { store: { name: 'Store C', code: 'multi_store_c', url: 'c.example.com' } }
    }.to change(PallasTrade::Store, :count).by(1)
    expect(response).to have_http_status(:redirect)

    store_c = PallasTrade::Store.find_by(code: 'multi_store_c')
    expect(store_c).to be_present
    expect(PallasTrade::RoleUser.where(user: admin, resource: store_c).exists?).to be(true)
    expect(session[:admin_store_id]).to eq(store_c.id)
  end

  # PRD-... AC-003
  it 'rejects a store without a name' do
    sign_in_as_superuser
    expect {
      post '/admin/stores', params: { store: { name: '', url: 'x.example.com' } }
    }.not_to change(PallasTrade::Store, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  # PRD-... AC-004
  it 'lists accessible stores in the switcher and switches the current store' do
    sign_in_as_superuser
    get '/admin/orders'
    expect(response).to have_http_status(:ok)
    # 超管可访问全部店铺 → 切换器含 Store A / B
    expect(response.body).to include('Store A')
    expect(response.body).to include('Store B')

    post '/admin/switch_store', params: { store_id: store_b.id }
    expect(response).to have_http_status(:redirect)
    expect(session[:admin_store_id]).to eq(store_b.id)

    # 切换后 current_store 生效（订单页仍可访问，当前店铺高亮 Store B）
    get '/admin/orders'
    expect(response).to have_http_status(:ok)
  end

  # PRD-... AC-004（无授权拒绝）
  it 'rejects switching to a store the user cannot access' do
    staff = create_staff_user(store_a)
    sign_in staff

    post '/admin/switch_store', params: { store_id: store_b.id }
    expect(session[:admin_store_id]).not_to eq(store_b.id)
    expect(response).to have_http_status(:redirect)
  end

  # PRD-... AC-005
  it 'hides store management from non-superusers and lists only their store in the switcher' do
    staff = create_staff_user(store_a)
    sign_in staff

    # 非超管访问店铺列表 → 授权失败重定向
    get '/admin/stores'
    expect(response).to have_http_status(:redirect)

    # 可访问的订单页：切换器仅列出授权的 store_a
    get '/admin/orders'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Store A')
    expect(response.body).not_to include('Store B')
  end

  # PRD-... AC-006
  it 'switcher still works with a single store' do
    store_b.destroy
    sign_in_as_superuser
    get '/admin/orders'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Store A')
  end

  # PRD-... AC-007
  it 'keeps the store edit page working after adding multi-store management' do
    sign_in_as_superuser
    get '/admin/store/edit'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store_a.name)
  end
end
