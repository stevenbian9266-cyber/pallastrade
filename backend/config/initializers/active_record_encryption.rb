# frozen_string_literal: true

# Configure Active Record Encryption for AI Provider secrets.
# In production, these values come from the deployment platform's Secret Manager
# (Render Env Vars, K8s Secrets, AWS SSM, etc.). For local development, they are
# set via environment variables in .env / docker-compose.yml.
#
# NOTE: application.rb already configures AR encryption conditionally when the
# env vars are present. This initializer is a no-op when vars are absent.
if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?
  Rails.application.config.active_record.encryption.primary_key = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
  Rails.application.config.active_record.encryption.deterministic_key = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
  Rails.application.config.active_record.encryption.key_derivation_salt = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']
end
