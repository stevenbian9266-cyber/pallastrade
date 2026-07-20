class AddPerformedByToSpreeReimbursements < ActiveRecord::Migration[6.1]
  def change
    add_reference :PALLASTRADE_reimbursements, :performed_by, index: true, null: true unless column_exists?(:PALLASTRADE_reimbursements, :performed_by_id)
  end
end
