# frozen_string_literal: true

require 'rails_helper'

# bugfix 2026-09-09：Store Details 直传 logo 失败时，signed_id 对应的 blob 文件可能未落盘
# （OSS CORS / 网络中断等），ActiveStorage 在 logo= 赋值阶段抛 FileNotFoundError → 500。
# StoresController#update 现在保存前校验直传附件，给出业务错误而非 500（en.yml store_errors.attachment_upload_incomplete）。
RSpec.describe 'Admin store settings — direct-upload attachment guard', type: :request do
  let!(:store) { create(:store, code: 'guard_store', name: 'Guard Store', url: 'guard.example.com', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def patch_store(overrides = {})
    patch '/admin/store', params: { store: { name: store.name, **overrides } }
  end

  def uploaded_png_blob
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1a\n#{'0' * 200}"),
      filename: 'guard_logo.png',
      content_type: 'image/png'
    )
  end

  it 'attaches the logo when the direct upload finished (file stored)' do
    blob = uploaded_png_blob
    patch_store(logo: blob.signed_id)

    expect(response).to have_http_status(:redirect)
    expect(store.reload.logo).to be_attached
    expect(store.logo.filename.to_s).to eq('guard_logo.png')
  end

  it 'returns a friendly error instead of 500 when the blob has no stored file yet' do
    # 复刻直传「blob 已建但文件未 PUT 成功」的场景（原 FileNotFoundError 500 触发条件）
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: 'guard_logo.png',
      byte_size: 200,
      checksum: Digest::MD5.base64digest('guard'),
      content_type: 'image/png'
    )

    patch_store(logo: blob.signed_id)

    expect(response).to have_http_status(:redirect)
    expect(store.reload.logo).not_to be_attached

    follow_redirect!
    expect(response.body).to include(PallasTrade.t('store_errors.attachment_upload_incomplete'))
  end

  it 'rejects a bogus signed id without crashing' do
    patch_store(logo: 'not-a-real-signed-id')

    expect(response).to have_http_status(:redirect)
    expect(store.reload.logo).not_to be_attached

    follow_redirect!
    expect(response.body).to include(PallasTrade.t('store_errors.attachment_upload_incomplete'))
  end

  it 'leaves the logo untouched when no logo param is submitted' do
    patch_store

    expect(response).to have_http_status(:redirect)
    expect(store.reload.logo).not_to be_attached
  end

  it 'renders the visible upload-error target on the store edit page' do
    get '/admin/store/edit'
    expect(response).to have_http_status(:ok)
    # 前端 uploader（_upload_form.html.erb）必须渲染错误提示容器，失败时由 JS 填充文案
    expect(response.body).to include('data-active-storage-upload-target="error"')
    expect(response.body).to include('role="alert"')
  end
end
