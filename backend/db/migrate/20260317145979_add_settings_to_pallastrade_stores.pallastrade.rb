# This migration comes from pallastrade (originally 20210930155649)
class AddSettingsToPallasTradeStores < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_stores do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_stores, :settings, :jsonb
      else
        add_column :pallastrade_stores, :settings, :json
      end
    end
  end
end
