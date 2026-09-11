# frozen_string_literal: true

# PRD-20260911-promotions-promo-batch6-pr-p9-cleanup (PR-P9-1, D1=A)
#
# 下线 v2 时代残留：`advertise`（仅被零调用方的 Product#possible_promotions 使用）
# 与 `path`（仅被零调用方的 PromotionHandler::Page 使用）。
# 上游列定义在 pallastrade_core/db/migrate/*_pallastrade_four_three.rb（历史迁移不改），
# 这里以新增迁移方式移除，保持 schema.rb 由迁移生成。
class RemoveAdvertiseAndPathFromPallasTradePromotions < ActiveRecord::Migration[8.1]
  def change
    remove_index :pallastrade_promotions, :advertise, if_exists: true
    remove_column :pallastrade_promotions, :advertise, :boolean
    remove_column :pallastrade_promotions, :path, :string
  end
end
