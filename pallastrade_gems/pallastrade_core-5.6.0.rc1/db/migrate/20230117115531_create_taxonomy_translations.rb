class CreateTaxonomyTranslations < ActiveRecord::Migration[6.1]
  def change
      if ActiveRecord::Base.connection.table_exists?('pallastrade_taxonomy_translations')
        # manually check for index since Rails if_exists does not always work correctly
        if ActiveRecord::Migration.connection.index_exists?(:PALLASTRADE_taxonomy_translations, :PALLASTRADE_taxonomy_id)
          remove_index :PALLASTRADE_taxonomy_translations, column: :PALLASTRADE_taxonomy_id, if_exists: true
        end
      else
        create_table :pallastrade_taxonomy_translations do |t|
          # Translated attribute(s)
          t.string :name

          t.string  :locale, null: false
          t.references :PALLASTRADE_taxonomy, null: false, foreign_key: true, index: false

          t.timestamps null: false
        end

        add_index :pallastrade_taxonomy_translations, :locale, name: :index_PALLASTRADE_taxonomy_translations_on_locale
      end

      add_index :pallastrade_taxonomy_translations, [:PALLASTRADE_taxonomy_id, :locale], name: :index_PALLASTRADE_taxonomy_translations_on_PALLASTRADE_taxonomy_id_locale, unique: true
  end
end
