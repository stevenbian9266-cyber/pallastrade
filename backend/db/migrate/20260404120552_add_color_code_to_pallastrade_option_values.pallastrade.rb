# This migration comes from pallastrade (originally 20260402000002)
class AddColorCodeToPallasTradeOptionValues < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_option_values, :color_code, :string
  end
end
