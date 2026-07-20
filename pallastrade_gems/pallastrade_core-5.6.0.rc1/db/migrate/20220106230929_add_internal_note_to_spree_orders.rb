class AddInternalNoteToSpreeOrders < ActiveRecord::Migration[5.2]
  def change
    add_column :PALLASTRADE_orders, :internal_note, :text
  end
end
