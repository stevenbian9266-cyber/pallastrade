# frozen_string_literal: true

require 'rails_helper'

# 修复：退出登录后按浏览器“后退”不应还原已登录的后台页面（2026-09-13 TASK-20260913050550）
# 1) 后台响应带 Cache-Control: private, no-store（与 API 层 PallasTrade::Api::V3::HttpCaching 一致）
#    → 浏览器不得直接复用本地缓存，后退时必须回服务器校验会话（未登录 → 302 登录页）
# 2) 布局内 pageshow 兜底：页面从 bfcache 还原时（此时不发请求、绕过 Cache-Control）强制刷新
RSpec.describe 'Admin page caching', type: :request do
  before do
    @admin = create(:admin_user, password: 'secret', password_confirmation: 'secret')

    get '/admin_user/sign_in'
    post '/admin_user/sign_in', params: {
      admin_user: { email: @admin.email, password: 'secret' }
    }
  end

  it 'sends no-store so a signed-in admin page is never reused after sign out' do
    get '/admin'

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
  end

  it 'forces a reload when the browser restores the page from the back-forward cache' do
    get '/admin'

    expect(response.body).to include('pageshow')
    expect(response.body).to include('location.reload')
  end
end
