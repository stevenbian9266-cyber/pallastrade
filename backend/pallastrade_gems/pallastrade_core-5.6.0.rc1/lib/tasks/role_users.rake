# frozen_string_literal: true

namespace :pallastrade do
  namespace :role_users do
    desc <<~DESC
      Backfills +pallastrade_role_users.store_id+ for store-scoped role assignments
      (resource_type = 'PallasTrade::Store') by copying +resource_id+. Idempotent —
      only rows with a null +store_id+ are touched.

      Role resolution (PallasTrade::Ability) scopes by +store_id+, so run this after
      adding the column. Until it does, the +pallastrade_admin?+ fallback keeps store
      admins authorized. Role assignments on non-store resources (e.g.
      PallasTrade::Vendor) are backfilled by the owning extension.
    DESC
    task backfill_store_ids: :environment do
      count = PallasTrade::RoleUser.where(resource_type: PallasTrade::Store.name, store_id: nil)
                             .update_all('store_id = resource_id')
      puts "  Backfilled store_id on #{count} store-scoped role assignment(s)."
    end
  end
end
