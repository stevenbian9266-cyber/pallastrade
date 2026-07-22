class CreatePallasTradePropertiesAndProductProperties < ActiveRecord::Migration[7.2]
  def json_column_type
    connection.adapter_name.downcase.include?('postgresql') ? :jsonb : :json
  end

  def change
    unless table_exists?(:pallastrade_properties)
      create_table :pallastrade_properties do |t|
        t.string :name
        t.string :presentation, null: false
        t.string :filter_param
        t.boolean :filterable, default: false, null: false
        t.integer :kind, default: 0
        t.string :display_on, default: 'both'
        t.integer :position, default: 0
        t.column :public_metadata, json_column_type
        t.column :private_metadata, json_column_type

        t.timestamps
      end

      add_index :pallastrade_properties, :name, unique: true
      add_index :pallastrade_properties, :filter_param
      add_index :pallastrade_properties, :filterable
      add_index :pallastrade_properties, :position
    end

    unless table_exists?(:pallastrade_product_properties)
      create_table :pallastrade_product_properties do |t|
        t.string :value
        t.references :product, null: false
        t.references :property, null: false
        t.integer :position, default: 0
        t.string :filter_param
        t.boolean :show_property, default: true

        t.timestamps
      end

      add_index :pallastrade_product_properties, [:property_id, :product_id], unique: true
      add_index :pallastrade_product_properties, :filter_param
      add_index :pallastrade_product_properties, :position
    end

    unless table_exists?(:pallastrade_property_prototypes)
      create_table :pallastrade_property_prototypes do |t|
        t.references :prototype
        t.references :property

        t.timestamps
      end

      add_index :pallastrade_property_prototypes, [:prototype_id, :property_id], unique: true, name: 'index_property_prototypes_on_prototype_id_and_property_id'
    end

    unless table_exists?(:pallastrade_property_translations)
      create_table :pallastrade_property_translations do |t|
        t.references :pallastrade_property, null: false
        t.string :locale, null: false
        t.string :presentation

        t.timestamps
      end

      add_index :pallastrade_property_translations, :locale
      add_index :pallastrade_property_translations, [:pallastrade_property_id, :locale], unique: true, name: 'unique_property_id_per_locale'
    end

    unless table_exists?(:pallastrade_product_property_translations)
      create_table :pallastrade_product_property_translations do |t|
        t.references :pallastrade_product_property, null: false
        t.string :locale, null: false
        t.string :value

        t.timestamps
      end

      add_index :pallastrade_product_property_translations, :locale
      add_index :pallastrade_product_property_translations, [:pallastrade_product_property_id, :locale], unique: true, name: 'unique_product_property_id_per_locale'
    end

    # For existing installations that already have these tables but may be missing columns
    if table_exists?(:pallastrade_properties)
      unless column_exists?(:pallastrade_properties, :public_metadata)
        add_column :pallastrade_properties, :public_metadata, json_column_type
      end

      unless column_exists?(:pallastrade_properties, :private_metadata)
        add_column :pallastrade_properties, :private_metadata, json_column_type
      end

      unless column_exists?(:pallastrade_properties, :display_on)
        add_column :pallastrade_properties, :display_on, :string, default: 'both'
      end

      unless column_exists?(:pallastrade_properties, :position)
        add_column :pallastrade_properties, :position, :integer, default: 0
      end

      unless column_exists?(:pallastrade_properties, :kind)
        add_column :pallastrade_properties, :kind, :integer, default: 0
      end

      unless column_exists?(:pallastrade_properties, :filter_param)
        add_column :pallastrade_properties, :filter_param, :string
      end

      unless column_exists?(:pallastrade_properties, :filterable)
        add_column :pallastrade_properties, :filterable, :boolean, default: false, null: false
      end
    end
  end
end
