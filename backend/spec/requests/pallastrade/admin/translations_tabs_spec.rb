# frozen_string_literal: true

require 'rails_helper'

# bug 2026-08-18：商品翻译抽屉 tab 全部显示 "English (US)"，无法区分语言。
# 根因：tab 直接 `t('i18n.this_file_language', locale:)`，该 key 仅 en.yml 定义；
# production `config.i18n.fallbacks = true` 时非 en 语言全部回退默认英文。
# 修复：tab 改用 `PallasTrade::Locale#label`（代码 + 本地化名），
# 并在 backend/config/locales/pallastrade_i18n.yml 为常用语言补 this_file_language。
RSpec.describe 'Admin translations drawer tabs', type: :request do
  let!(:store) do
    create(:store, code: 'trans_tabs', name: 'Trans Tabs Store', url: 'tabs.example.com',
                   default: true, default_locale: 'en', supported_locales: 'de,fr')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let!(:product) { create(:product, store: store, name: 'Tab Test Product') }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  # AC-001：多语言店铺抽屉各 tab 带语言代码 + 本地化名，可区分，不再全部 "English (US)"
  it 'renders distinct locale labels in the translations drawer tabs' do
    sign_in_as_superuser
    get "/admin/translations/PallasTrade::Product/#{product.to_param}/edit"
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('DE — Deutsch')
    expect(body).to include('FR — Français')
    expect(body).not_to include('English (US)')
  end

  # AC-002：无多语言（@locales 为空）时抽屉显示引导而非崩溃（回归）
  it 'falls back to the no-locales prompt for single-locale stores' do
    store.update!(supported_locales: 'en')
    sign_in_as_superuser
    get "/admin/translations/PallasTrade::Product/#{product.to_param}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.translations.no_translations_configured'))
  end
end
