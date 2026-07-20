class RemoveNotNullConstraintFromPolicyName < ActiveRecord::Migration[7.2]
  def change
    change_column_null :PALLASTRADE_policies, :name, true
  end
end
