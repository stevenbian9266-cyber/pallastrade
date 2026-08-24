# frozen_string_literal: true

require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-032 / AC-032
# 父子单视图展示各子订单发货进度
RSpec.describe 'Admin orders show — 子订单发货进度（父子单视图）', type: :request do
  let(:store) { create(:store, code: 'child_shipments_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
  end

  def order_doc
    Nokogiri::HTML(response.body)
  end

  it 'AC-032: 父订单视图展示各子订单发货进度（订单号 + 发货状态）' do
    parent = create(:order_with_line_items, store: store, user: create(:user), currency: 'USD')
    target = parent.line_items.first
    split_result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [target.id] })
    child = split_result.value.first
    expect(child.shipments.size).to eq(1)

    get PallasTrade.admin_order_path(parent)

    expect(response).to have_http_status(:ok)
    doc = order_doc
    # 子订单发货进度区块包含子订单号
    expect(doc.css('h5').any? { |h| h.text.include?('Sub-order Shipments') }).to be true
    expect(doc.text).to include(child.number)
    expect(doc.text).to include('Shipments')
  end
end
