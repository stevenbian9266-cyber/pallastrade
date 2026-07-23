# This migration comes from pallastrade (originally 20260613000001)
class AddStoreIdToPallasTradeRoleUsers < ActiveRecord::Migration[7.2]
  def change
    # Denormalizes the store a role assignment applies within, so role
    # resolution (PallasTrade::Ability) can scope by store without depending on the
    # polymorphic resource. Kept null: true here; existing rows are backfilled
    # by `pallastrade:role_users:backfill_store_ids` and presence is enforced
    # on the model.
    add_reference :pallastrade_role_users, :store, null: true
  end
end
