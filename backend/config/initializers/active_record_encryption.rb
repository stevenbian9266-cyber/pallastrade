# frozen_string_literal: true

# Configure Active Record Encryption for AI Provider secrets.
# In production, these values come from the deployment platform's Secret Manager
# (Render Env Vars, K8s Secrets, AWS SSM, etc.). For local development, they are
# set via environment variables in .env / docker-compose.yml.
Rails.application.config.active_record.encryption.primary_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
