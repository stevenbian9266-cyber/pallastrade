# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-5 (PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept)
#
# 退货 restock exactly-once（源文档 REV-P6 §42）：
#   - stock_movements.return_item_id（可空）——退货 restock 的稳定幂等键。
#     originator=ReturnAuthorization 为一对多不可作唯一键，故以 return_item_id 承担。
#   - partial unique index（return_item_id IS NOT NULL）：同一 return_item 至多一条正向 movement；
#     应用层 RecordNotUnique 幂等跳过（重复/重试/并发）。
# 语义冻结：one logical restock → at most one physical positive movement。
class AddReturnItemToPallasTradeStockMovements < ActiveRecord::Migration[8.1]
  def up
    add_reference :pallastrade_stock_movements, :return_item,
                  foreign_key: { to_table: :pallastrade_return_items }, index: false
    add_index :pallastrade_stock_movements, :return_item_id,
              unique: true, where: 'return_item_id IS NOT NULL',
              name: 'idx_stock_movements_return_item_unique'
  end

  def down
    remove_index :pallastrade_stock_movements, name: 'idx_stock_movements_return_item_unique'
    remove_reference :pallastrade_stock_movements, :return_item
  end
end
