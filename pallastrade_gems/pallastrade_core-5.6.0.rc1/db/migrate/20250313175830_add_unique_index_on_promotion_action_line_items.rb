class AddUniqueIndexOnPromotionActionLineItems < ActiveRecord::Migration[7.2]
  def change
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      # Remove duplicate promotion action line items
      execute <<-SQL
        DELETE FROM PALLASTRADE_promotion_action_line_items
        WHERE id NOT IN (
          SELECT mid FROM (
            SELECT MIN(id) AS mid
            FROM PALLASTRADE_promotion_action_line_items
            GROUP BY promotion_action_id, variant_id
          ) AS min_ids
        );
      SQL
    else
      # Remove duplicate promotion action line items
      execute <<-SQL
        DELETE FROM PALLASTRADE_promotion_action_line_items
        WHERE id NOT IN (
          SELECT MIN(id)
          FROM PALLASTRADE_promotion_action_line_items
          GROUP BY promotion_action_id, variant_id
        );
      SQL
    end

    add_index :pallastrade_promotion_action_line_items, [:promotion_action_id, :variant_id], unique: true
  end
end
