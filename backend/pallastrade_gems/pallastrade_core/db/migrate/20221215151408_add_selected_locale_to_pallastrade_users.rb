class AddSelectedLocaleToPallasTradeUsers < ActiveRecord::Migration[6.1]
  def change
    if PallasTrade.user_class.present?
      users_table_name = PallasTrade.user_class.table_name
      add_column users_table_name, :selected_locale, :string unless column_exists?(users_table_name, :selected_locale)
    end
  end
end
