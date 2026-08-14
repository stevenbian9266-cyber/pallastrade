# frozen_string_literal: true

# Config Center — boot-time integration.
#
# 1. Merges managed Config Center values into ENV (Config Center ALWAYS wins;
#    it is the single source of truth — ENV is only a boot fallback), so
#    legacy `ENV[...]` read sites pick up the managed value.
# 2. Re-resolves the Active Storage service once the DB is available and ENV is
#    enriched (the boot-time selection in config/environments/*.rb may have
#    picked `:local` because the DB wasn't ready yet).
#
# Fail-open: if the DB isn't ready (first boot, migrations pending), we keep the
# existing ENV / boot-time selection and log a warning.
Rails.application.config.after_initialize do
  begin
    PallasTrade::ConfigCenter.sync_env!

    service = PallasTrade::Storage::ServiceResolver.resolve
    if Rails.application.config.active_storage.service != service
      Rails.application.config.active_storage.service = service
      Rails.logger.info("[ConfigCenter] active_storage service resolved to #{service}")
    end
  rescue StandardError => e
    Rails.logger.warn("[ConfigCenter] boot sync skipped: #{e.class}: #{e.message}")
  end
end
