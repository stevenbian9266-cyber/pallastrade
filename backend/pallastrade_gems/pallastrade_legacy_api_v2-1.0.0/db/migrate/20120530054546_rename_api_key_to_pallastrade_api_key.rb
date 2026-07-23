class RenameApiKeyToPallasTradeApiKey < ActiveRecord::Migration[4.2]
  def change
    unless defined?(User)
      rename_column :pallastrade_users, :api_key, :pallastrade_api_key
    end
  end
end
