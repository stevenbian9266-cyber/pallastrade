# This migration comes from pallastrade (originally 20260117140831)
class RemoveNotNullConstraintFromPolicyName < ActiveRecord::Migration[7.2]
  def change
    change_column_null :pallastrade_policies, :name, true
  end
end
