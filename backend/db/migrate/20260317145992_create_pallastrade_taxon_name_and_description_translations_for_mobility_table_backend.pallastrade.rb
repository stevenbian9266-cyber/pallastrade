# This migration comes from pallastrade (originally 20220718100743)
class CreatePallasTradeTaxonNameAndDescriptionTranslationsForMobilityTableBackend < ActiveRecord::Migration[6.1]
  def change
    # create translation table only if pallastrade_globalize has not already created it
    if ActiveRecord::Base.connection.table_exists? 'pallastrade_taxon_translations'
      # manually check for index since Rails if_exists does not always work correctly
      if ActiveRecord::Migration.connection.index_exists?(:pallastrade_taxon_translations, :pallastrade_taxon_id)
        # replacing this with index on pallastrade_taxon_id and locale
        remove_index :pallastrade_taxon_translations, name: "index_pallastrade_taxon_translations_on_pallastrade_taxon_id", if_exists: true
      end
    else
      create_table :pallastrade_taxon_translations do |t|
        # Translated attribute(s)
        t.string :name
        t.text :description

        t.string  :locale, null: false
        t.references :pallastrade_taxon, null: false, foreign_key: true, index: false

        t.timestamps null: false
      end

      add_index :pallastrade_taxon_translations, :locale, name: :index_pallastrade_taxon_translations_on_locale
    end

    add_index :pallastrade_taxon_translations, [:pallastrade_taxon_id, :locale], name: :index_pallastrade_taxon_translations_on_pallastrade_taxon_id_and_locale, unique: true
  end
end
