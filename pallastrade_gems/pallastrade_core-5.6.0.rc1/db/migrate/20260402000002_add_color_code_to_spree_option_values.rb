class AddColorCodeToSpreeOptionValues < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_option_values, :color_code, :string
  end
end
