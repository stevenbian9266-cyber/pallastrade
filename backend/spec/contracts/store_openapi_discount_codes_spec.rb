# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-discount-codes-canonical AC-007：
# 契约同步守卫 —— `discount_codes` 端点的语义说明必须在两份 Store OpenAPI
# （`backend/public/api-docs` 与 `platform/docs/api-reference`）保持一致，
# 且必须写明“应用不消耗码 / 提交时才核销”这一关键语义，防止文档漂移。
RSpec.describe 'Store OpenAPI discount_codes contract' do
  let(:backend_yaml) { Rails.root.join('public/api-docs/store.yaml') }

  # 平台副本（`platform/docs/api-reference/store.yaml`）在本容器内可能不可见
  # （backend 容器只挂载 `backend/`）—— 可见时做漂移对比，不可见时仅校验语义。
  def platform_yaml
    relative = 'platform/docs/api-reference/store.yaml'
    root = Pathname.new(Rails.root).ascend.find { |dir| (dir + relative).exist? }
    root && (root + relative)
  end

  def description_of(file)
    File.read(file)[/Applies a promotion discount code to the cart\..*?endpoint instead\./m]
  end

  it 'keeps the POST /carts/{cart_id}/discount_codes description identical in both copies' do
    skip 'platform docs copy not available in this environment' if platform_yaml.nil?

    backend = description_of(backend_yaml)
    platform = description_of(platform_yaml)

    expect(backend).to be_present
    expect(platform).to eq(backend)
  end

  it 'documents the apply-does-not-consume semantics and the cart_ error codes' do
    backend = description_of(backend_yaml)

    expect(backend).to include('private_metadata.discount_code')
    expect(backend).to include('coupon_code_not_found')
    expect(backend).to include('coupon_code_expired')
    expect(backend).to include('does **not** consume')
  end
end
