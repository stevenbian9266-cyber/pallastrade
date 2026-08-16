# frozen_string_literal: true

class CreatePallasTradePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_posts do |t|
      t.belongs_to :store, null: false
      t.string :slug, null: false
      t.string :title, null: false
      t.text :excerpt
      t.string :author
      t.datetime :published_at
      t.string :seo_title
      t.text :seo_description

      t.timestamps
    end

    add_index :pallastrade_posts, [:store_id, :slug], unique: true
    add_index :pallastrade_posts, [:store_id, :published_at]

    create_table :pallastrade_post_translations do |t|
      t.string :locale, null: false
      t.string :title
      t.text :excerpt
      t.string :seo_title
      t.text :seo_description
      t.references :pallastrade_post, null: false

      t.timestamps
    end

    add_index :pallastrade_post_translations, [:pallastrade_post_id, :locale], unique: true
  end
end
