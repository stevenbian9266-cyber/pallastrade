class AddIndexToUserPallasTradeApiKey < ActiveRecord::Migration[4.2]
  def change
    unless defined?(User)
      add_index :pallastrade_users, :pallastrade_api_key
    end
  end
end
