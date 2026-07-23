# This migration comes from pallastrade (originally 20260315100000)
class AddProductMediaSupport < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_assets, :media_type, :string
    add_column :pallastrade_assets, :focal_point_x, :decimal, precision: 5, scale: 4
    add_column :pallastrade_assets, :focal_point_y, :decimal, precision: 5, scale: 4
    add_column :pallastrade_assets, :external_video_url, :string

    add_index :pallastrade_assets, :media_type

    rename_column :pallastrade_variants, :image_count, :media_count
    rename_column :pallastrade_products, :total_image_count, :media_count
    rename_column :pallastrade_variants, :thumbnail_id, :primary_media_id
    rename_column :pallastrade_products, :thumbnail_id, :primary_media_id

    reversible do |dir|
      dir.up do
        PallasTrade::Asset.unscoped.where(media_type: nil).update_all(media_type: 'image')
      end
    end
  end
end
