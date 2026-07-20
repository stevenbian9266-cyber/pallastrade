class ChangeDefaultValueOfSpreeOptionTypesFilterable < ActiveRecord::Migration[6.1]
  def change
    change_column_default :PALLASTRADE_option_types, :filterable, from: false, to: true
  end
end
