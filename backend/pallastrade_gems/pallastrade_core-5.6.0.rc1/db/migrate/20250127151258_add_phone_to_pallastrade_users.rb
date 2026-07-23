class AddPhoneToPallasTradeUsers < ActiveRecord::Migration[6.1]
  def change
    add_column PallasTrade.user_class.table_name, :phone, :string, if_not_exists: true
  end
end
