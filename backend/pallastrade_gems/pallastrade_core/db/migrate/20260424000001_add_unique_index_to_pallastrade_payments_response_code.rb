class AddUniqueIndexToPallasTradePaymentsResponseCode < ActiveRecord::Migration[7.2]
  def up
    # Remove duplicate payments per (order, payment_method, response_code),
    # preferring to keep completed payments over incomplete ones.
    # Among same-state duplicates, keeps the most recent (highest id).
    # Uses derived table for MySQL compatibility.
    execute <<~SQL
      DELETE FROM pallastrade_payments
      WHERE response_code IS NOT NULL
        AND id NOT IN (
          SELECT keeper_id FROM (
            SELECT (
              SELECT id FROM pallastrade_payments p2
              WHERE p2.order_id = p1.order_id
                AND p2.payment_method_id = p1.payment_method_id
                AND p2.response_code = p1.response_code
              ORDER BY
                CASE p2.state
                  WHEN 'completed' THEN 0
                  WHEN 'pending'   THEN 1
                  WHEN 'processing' THEN 2
                  ELSE 3
                END,
                p2.id DESC
              LIMIT 1
            ) AS keeper_id
            FROM pallastrade_payments p1
            WHERE p1.response_code IS NOT NULL
            GROUP BY p1.order_id, p1.payment_method_id, p1.response_code
          ) AS keeper_ids
        )
    SQL

    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      # MySQL doesn't support partial indexes, but treats NULL as distinct
      # in unique indexes so multiple payments with NULL response_code are allowed
      add_index :pallastrade_payments, [:order_id, :payment_method_id, :response_code],
                unique: true,
                name: 'idx_payments_order_method_response_code'
    else
      add_index :pallastrade_payments, [:order_id, :payment_method_id, :response_code],
                unique: true,
                where: 'response_code IS NOT NULL',
                name: 'idx_payments_order_method_response_code'
    end
  end

  def down
    remove_index :pallastrade_payments, name: 'idx_payments_order_method_response_code'
  end
end
