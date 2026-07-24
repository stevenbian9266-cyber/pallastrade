class CreatePallasTradeProductSlugTranslationsForMobilityTableBackend < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_product_translations, :slug, :string
  end
end
