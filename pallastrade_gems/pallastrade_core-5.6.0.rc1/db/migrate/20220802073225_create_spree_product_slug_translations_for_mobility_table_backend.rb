class CreateSpreeProductSlugTranslationsForMobilityTableBackend < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_product_translations, :slug, :string
  end
end
