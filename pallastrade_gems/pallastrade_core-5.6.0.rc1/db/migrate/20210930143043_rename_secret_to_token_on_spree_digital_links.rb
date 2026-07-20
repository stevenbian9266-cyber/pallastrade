class RenameSecretToTokenOnSpreeDigitalLinks < ActiveRecord::Migration[5.2]
  def change
    rename_column :PALLASTRADE_digital_links, :secret, :token
  end
end
