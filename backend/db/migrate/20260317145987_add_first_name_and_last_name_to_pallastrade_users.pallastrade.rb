# This migration comes from pallastrade (originally 20220201103922)
class AddFirstNameAndLastNameToPallasTradeUsers < ActiveRecord::Migration[5.2]
  def change
    if PallasTrade.user_class.present?
      users_table_name = PallasTrade.user_class.table_name
      add_column users_table_name, :first_name, :string unless column_exists?(users_table_name, :first_name)
      add_column users_table_name, :last_name, :string unless column_exists?(users_table_name, :last_name)
    end
  end
end
