# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot (FR-001, D1)
#
# 成交快照列：订单资金确认（legacy `complete` / 标准流程 `paid` /
# `commerce_transaction.payment_confirmed`）时，把当时的促销展示事实
# （name / kind / code / description / 三分项金额 / 币种 / 定义摘要）固化到
# `pallastrade_order_promotions`，此后促销改名/改 kind/停用码/删动作都不会
# 再影响历史订单展示（架构 §35 Promotion Snapshot、§134 Order Snapshot 分离）。
#
# 纯增量：全部列 nullable（金额列带默认值），不需要回填即可部署；
# 存量订单由 `rake pallastrade:promotions:backfill_order_promotion_snapshots` 冻结。
class AddSnapshotToPallasTradeOrderPromotions < ActiveRecord::Migration[8.1]
  AMOUNT_COLUMNS = %i[item_amount order_amount shipping_amount total_amount].freeze

  def change
    add_column :pallastrade_order_promotions, :name, :string
    add_column :pallastrade_order_promotions, :kind, :string
    add_column :pallastrade_order_promotions, :code, :string
    add_column :pallastrade_order_promotions, :description, :string
    add_column :pallastrade_order_promotions, :definition_digest, :string

    AMOUNT_COLUMNS.each do |column|
      add_column :pallastrade_order_promotions, column, :decimal,
                 precision: 10, scale: 2, default: 0.0, null: false
    end

    add_column :pallastrade_order_promotions, :currency, :string
    add_column :pallastrade_order_promotions, :frozen_at, :datetime

    add_index :pallastrade_order_promotions, :frozen_at,
              name: 'index_pt_order_promotions_on_frozen_at'
  end
end
