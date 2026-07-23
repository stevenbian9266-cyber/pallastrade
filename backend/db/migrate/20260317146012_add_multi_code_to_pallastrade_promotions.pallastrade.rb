# This migration comes from pallastrade (originally 20241005093437)
class AddMultiCodeToPallasTradePromotions < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_promotions, :code_prefix, :string, if_not_exists: true
    add_column :pallastrade_promotions, :number_of_codes, :integer, if_not_exists: true
    add_column :pallastrade_promotions, :kind, :integer, default: 0, if_not_exists: true
    add_column :pallastrade_promotions, :multi_codes, :boolean, default: false, if_not_exists: true

    add_index :pallastrade_promotions, :kind, if_not_exists: true

    unless Rails.env.test?
      PallasTrade::Promotion.reset_column_information
      # set all promotions without a code to automatic
      PallasTrade::Promotion.where(code: [nil, '']).update_all(kind: 1)
    end
  end
end
