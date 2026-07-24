class AddProcessingGroupsToPallasTradeImports < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_imports, :processing_groups_count, :integer, default: 0
    add_column :pallastrade_imports, :completed_groups_count, :integer, default: 0
  end
end
