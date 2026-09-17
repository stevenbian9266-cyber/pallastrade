# frozen_string_literal: true

# PALLAS-CUSTOM: 结构化退货条款的存储底座（PRD-20260917-catalog-json-ld-phase2 FR-005）
#
# 为什么需要它：schema.org 的 `hasMerchantReturnPolicy` 要求**结构化**条款
# （类目 / 窗口天数 / 退货方式 / 费用承担方 / 适用国家），而退货政策目前只有正文文本。
# 只输出一个政策 URL 并不满足富媒体摘要的要求，所以必须把条款本身结构化。
#
# 为什么是**通用** `preferences` 列，而不是退货专用列：
#   * `PallasTrade::Policy` 是**通用**模型（隐私 / 配送 / 退货 / 条款四类共用），
#     加退货专用列会让另外三类政策永久多出一排全为 NULL 的列；
#   * 枚举与天数一旦进表结构就难以演进（每加一个取值都要迁移）；
#   * `preferences` 是仓库**既有机制**（`pallastrade_stores.preferences` 同款），
#     由 `PallasTrade::Preferences::Preferable` 提供类型化读写，条款可以随
#     schema.org 演进继续加，不需要每次迁移。
#
# 只加列，不建索引、不回填：未设置的记录读出来就是空，
# 与前端「缺数据即省略该字段」的约定一致（绝不输出编造的退货政策）。
class AddPreferencesToPallasTradePolicies < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:pallastrade_policies, :preferences)

    add_column :pallastrade_policies, :preferences, :text
  end
end
