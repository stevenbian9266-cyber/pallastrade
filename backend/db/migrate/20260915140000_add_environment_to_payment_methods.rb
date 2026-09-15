# frozen_string_literal: true

# D9（PRD-20260915-payments-d9-支付凭据与环境 切片1）：
# provider 增加 **环境维度**（test / live）——后台可切、**不重启、不重建镜像**（业务方案 §68.1）。
#
# 默认 'live' + null: false → 存量数据零回归（历史 provider 视同生产）；
# test 环境 provider 不进前台列表（`Payments::Availability::Resolver` 的 frontend scope 过滤）。
class AddEnvironmentToPaymentMethods < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_payment_methods, :environment, :string, default: 'live', null: false
  end
end
