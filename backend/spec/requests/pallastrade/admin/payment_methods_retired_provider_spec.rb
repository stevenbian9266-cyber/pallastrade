# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260921130000_remove_retired_provider_payment_methods')

# 收敛切片 5 回归修复（2026-09-21）—— 已下线厂商的历史 STI 行不得再拖垮读路径。
#
# 背景：切片 5 删除了 `pallastrade_adyen` / `pallastrade_paypal_checkout` 两个 gem
# （连同 STI 类），但库里仍可能有 `type` 指向已删类的历史行。ActiveRecord 实例化这类行时抛
# `ActiveRecord::SubclassNotFound`，且**整条查询一起失败** —— dev 后台「支付方式」列表
# 整页 500 且响应体为空（= 用户报告的「空白页」）。
#
# 修复分两层：
#   读路径容错（C）：`PaymentMethod.loadable` 在 SQL 层排除不可解析的行（列表不回炸）；
#                    `PaymentMethod.sti_class_for` 兜底为基类（非列表路径不回炸）。
#   数据清理（B）：`RemoveRetiredProviderPaymentMethods` 软删除已下线厂商的行。
#
# 设计取舍：本表 `acts_as_paranoid`（`deleted_at`）且被 `pallastrade_payment_sources`
# 以 NO ACTION 外键引用 → **软删除**既让行从应用层消失，又不改写资金记录的历史引用。
RSpec.describe 'Retired provider payment methods', type: :request do
  let!(:store) { create(:store, code: "retired_pm_#{SecureRandom.hex(4)}", name: 'Retired PM Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  # 已下线厂商：类不存在，只能用裸 SQL 造这条历史行（正是生产/ dev 的真实形态）
  RETIRED_TYPE = 'PallasTradeAdyen::Gateway'
  RETIRED_NAME = 'ZZZ Retired Adyen'

  def insert_retired_row(name: RETIRED_NAME, active: true)
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO pallastrade_payment_methods
        (type, name, active, display_on, created_at, updated_at)
      VALUES
        (#{ActiveRecord::Base.connection.quote(RETIRED_TYPE)},
       #{ActiveRecord::Base.connection.quote(name)},
       #{active ? 'TRUE' : 'FALSE'}, 'both', NOW(), NOW())
    SQL
    ActiveRecord::Base.connection.select_value(
      "SELECT id FROM pallastrade_payment_methods WHERE name = #{ActiveRecord::Base.connection.quote(name)}"
    ).to_i
  end

  def retired_row(id)
    ActiveRecord::Base.connection.select_one(
      "SELECT id, active, deleted_at FROM pallastrade_payment_methods WHERE id = #{id.to_i}"
    )
  end

  def sign_in_as_superuser
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  # 测试卫生：裸 SQL 造的行不受事务内 AR 回调管理，显式清掉，避免污染同库其它用例
  after do
    ActiveRecord::Base.connection.execute(
      "DELETE FROM pallastrade_payment_methods WHERE type = #{ActiveRecord::Base.connection.quote(RETIRED_TYPE)}"
    )
  end

  describe '读路径容错（C）' do
    it 'PaymentMethod.all 不再因不可解析的行而整条查询抛错' do
      insert_retired_row

      expect { PallasTrade::PaymentMethod.all.to_a }.not_to raise_error
    end

    it 'loadable 在 SQL 层排除不可解析的行，但不影响注册表内的类型' do
      retired_id = insert_retired_row
      stripe = create(:stripe_gateway, store: store)

      ids = PallasTrade::PaymentMethod.loadable.pluck(:id)

      expect(ids).not_to include(retired_id)
      expect(ids).to include(stripe.id)
    end

    # 不可判定不猜：类型无法解析时降级为基类并留痕，绝不炸掉整个请求
    it 'sti_class_for 对未知类型降级为基类，对已知类型保持原样' do
      expect(PallasTrade::PaymentMethod.sti_class_for(RETIRED_TYPE)).to eq(PallasTrade::PaymentMethod)
      expect(PallasTrade::PaymentMethod.sti_class_for('PallasTradeStripe::Gateway'))
        .to eq(PallasTradeStripe::Gateway)
    end
  end

  describe '后台列表（C，用户报告的实际入口）' do
    it 'GET /admin/payment_methods 返回 200，且不渲染已下线厂商的历史行' do
      insert_retired_row
      sign_in_as_superuser

      get '/admin/payment_methods'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(RETIRED_NAME)
    end
  end

  describe 'Admin API 列表（C）' do
    include_context 'API v3 Admin authenticated'

    it 'GET /api/v3/admin/payment_methods 返回 200，且不下发已下线厂商的历史行' do
      insert_retired_row

      get '/api/v3/admin/payment_methods', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data].map { |d| d[:attributes][:name] }).not_to include(RETIRED_NAME)
    end
  end

  describe '数据清理迁移（B）' do
    it '软删除已下线厂商的行：deleted_at 落值、active 置否、不再出现在默认集合中' do
      retired_id = insert_retired_row

      RemoveRetiredProviderPaymentMethods.new.migrate(:up)

      row = retired_row(retired_id)
      expect(row['deleted_at']).to be_present
      expect(row['active']).to be(false)
      expect(PallasTrade::PaymentMethod.all.pluck(:id)).not_to include(retired_id)
    end

    it '注册表内类型的行不受影响' do
      stripe = create(:stripe_gateway, store: store)

      RemoveRetiredProviderPaymentMethods.new.migrate(:up)

      expect(retired_row(stripe.id)['deleted_at']).to be_nil
      expect(retired_row(stripe.id)['active']).to be(true)
    end

    it '声明为不可逆，避免误回滚丢失软删除事实' do
      expect { RemoveRetiredProviderPaymentMethods.new.migrate(:down) }
        .to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
