class AddSettingsToSpreeStores < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_stores do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_stores, :settings, :jsonb
      else
        add_column :PALLASTRADE_stores, :settings, :json
      end
    end
  end
end
