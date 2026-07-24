class AddPreferencesToPallasTradeExports < ActiveRecord::Migration[7.2]
  def change
    # Same serialized preferences store pallastrade_imports already has — first
    # consumer is the `results_url` the export-done email links back to.
    add_column :pallastrade_exports, :preferences, :text
  end
end
