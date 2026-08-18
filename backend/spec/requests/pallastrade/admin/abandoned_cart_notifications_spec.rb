# frozen_string_literal: true

require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

# PRD-20260818-other-p0-3-邮件自动化-弃单恢复
# AC-005：Admin 弃单通知页（列表 + 手动触发扫描）
RSpec.describe 'Admin abandoned cart notifications', type: :request do
  let!(:store) { create(:store, code: 'abn_admin_store', name: 'Abn Store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let!(:notification) do
    cart = create(:order, store: store, email: 'buyer@example.com', state: 'cart', user: nil)
    store.abandoned_cart_notifications.create!(cart: cart, email: cart.email).tap(&:mark_sent!)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::AbandonedCartNotificationsController).to receive(:current_store).and_return(store)
  end

  it 'lists abandoned cart notifications for the current store' do
    sign_in_as_superuser
    get '/admin/abandoned_cart_notifications'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('buyer@example.com')
    expect(response.body).to include(PallasTrade.t('admin.abandoned_cart_notifications.title'))
  end

  it 'enqueues a scan via the run action' do
    sign_in_as_superuser
    expect {
      post '/admin/abandoned_cart_notifications/run'
    }.to have_enqueued_job(PallasTrade::AbandonedCarts::SendNotificationsJob).with(hash_including(store_id: store.id))
    expect(response).to have_http_status(:redirect)
  end
end
