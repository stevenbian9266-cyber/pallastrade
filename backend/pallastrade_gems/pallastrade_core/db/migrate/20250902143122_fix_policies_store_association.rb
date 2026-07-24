class FixPoliciesStoreAssociation < ActiveRecord::Migration[7.2]
  def change
    add_reference :pallastrade_policies, :owner, polymorphic: true, index: true

    PallasTrade::Policy.reset_column_information
    PallasTrade::Policy.all.each do |policy|
      policy.update(owner_id: policy.store_id, owner_type: 'PallasTrade::Store')
    end

    remove_index :pallastrade_policies, [:store_id, :slug], unique: true, if_exists: true
    remove_index :pallastrade_policies, [:store_id, :position], if_exists: true
    remove_column :pallastrade_policies, :store_id, if_exists: true
    remove_column :pallastrade_policies, :show_in_checkout_footer, if_exists: true
    remove_column :pallastrade_policies, :position, if_exists: true

    add_index :pallastrade_policies, [:owner_id, :owner_type, :slug], unique: true
  end
end
