class AddPriceListIdToPallasTradePrices < ActiveRecord::Migration[7.0]
  def change
    add_reference :pallastrade_prices, :price_list, null: true
    add_index :pallastrade_prices, [:variant_id, :currency, :price_list_id], name: 'index_pallastrade_prices_on_variant_currency_price_list', unique: true
  end
end
