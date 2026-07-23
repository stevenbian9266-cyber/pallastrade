# This migration comes from pallastrade (originally 20260429000004)
class AddScopesToPallasTradeApiKeys < ActiveRecord::Migration[7.2]
  def change
    change_table :pallastrade_api_keys do |t|
      if t.respond_to?(:jsonb)
        t.jsonb :scopes
      else
        t.json :scopes
      end
    end
  end
end
