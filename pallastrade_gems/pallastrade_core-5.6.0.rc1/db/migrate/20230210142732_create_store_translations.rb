class CreateStoreTranslations < ActiveRecord::Migration[6.1]
  def change
    if ActiveRecord::Base.connection.table_exists?('pallastrade_store_translations')
      add_new_translation_columns_to_globalize_table
    else
      create_table :pallastrade_store_translations do |t|
        # Translated attribute(s)
        t.string :name
        t.text :meta_description
        t.text :meta_keywords
        t.string :seo_title
        t.string :facebook
        t.string :twitter
        t.string :instagram
        t.string :customer_support_email
        t.text :description
        t.text :address
        t.string :contact_phone
        t.string :new_order_notifications_email

        t.string  :locale, null: false
        t.references :PALLASTRADE_store, null: false, foreign_key: true, index: false

        t.timestamps null: false
      end

      add_index :pallastrade_store_translations, :locale, name: :index_PALLASTRADE_store_translations_on_locale
    end

    add_index :pallastrade_store_translations, [:PALLASTRADE_store_id, :locale], name: :index_PALLASTRADE_store_translations_on_PALLASTRADE_store_id_locale, unique: true
  end

  private

  def add_new_translation_columns_to_globalize_table
    # manually check for index since Rails if_exists does not always work correctly
    if ActiveRecord::Migration.connection.index_exists?(:PALLASTRADE_store_translations, :PALLASTRADE_store_id)
      remove_index :PALLASTRADE_store_translations, column: :PALLASTRADE_store_id, if_exists: true
    end

    add_column :PALLASTRADE_store_translations, :facebook, :string
    add_column :PALLASTRADE_store_translations, :twitter, :string
    add_column :PALLASTRADE_store_translations, :instagram, :string
    add_column :PALLASTRADE_store_translations, :customer_support_email, :string
    add_column :PALLASTRADE_store_translations, :description, :text
    add_column :PALLASTRADE_store_translations, :address, :text
    add_column :PALLASTRADE_store_translations, :contact_phone, :string
    add_column :PALLASTRADE_store_translations, :new_order_notifications_email, :string
  end
end
