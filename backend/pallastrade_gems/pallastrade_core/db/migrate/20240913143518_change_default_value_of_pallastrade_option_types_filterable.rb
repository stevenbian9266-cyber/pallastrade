class ChangeDefaultValueOfPallasTradeOptionTypesFilterable < ActiveRecord::Migration[6.1]
  def change
    change_column_default :pallastrade_option_types, :filterable, from: false, to: true
  end
end
