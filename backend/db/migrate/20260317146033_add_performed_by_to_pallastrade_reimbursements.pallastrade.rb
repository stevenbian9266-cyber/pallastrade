# This migration comes from pallastrade (originally 20250304115943)
class AddPerformedByToPallasTradeReimbursements < ActiveRecord::Migration[6.1]
  def change
    add_reference :pallastrade_reimbursements, :performed_by, index: true, null: true unless column_exists?(:pallastrade_reimbursements, :performed_by_id)
  end
end
