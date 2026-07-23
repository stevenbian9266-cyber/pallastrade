# This migration comes from pallastrade (originally 20220117100333)
class AddMakeActiveAtToPallasTradeProducts < ActiveRecord::Migration[5.2]
  def change
    add_column :pallastrade_products, :make_active_at, :datetime
    add_index :pallastrade_products, :make_active_at

    PallasTrade::Product.
      where('discontinue_on IS NULL or discontinue_on > ?', Time.current).
      where('available_on <= ?', Time.current).
      where(status: 'draft').
      update_all(status: 'active', updated_at: Time.current)

    PallasTrade::Product.
      where('discontinue_on <= ?', Time.current).
      where.not(status: 'archived').
      update_all(status: 'archived', updated_at: Time.current)
  end
end
