class RenameSecretToTokenOnPallasTradeDigitalLinks < ActiveRecord::Migration[5.2]
  def change
    rename_column :pallastrade_digital_links, :secret, :token
  end
end
