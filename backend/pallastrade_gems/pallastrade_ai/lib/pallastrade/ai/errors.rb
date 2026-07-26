# frozen_string_literal: true

module PallasTrade
  module AI
    module Errors
      # Base error class for all AI module errors.
      class Error < StandardError; end

      # Raised when Active Record Encryption is not configured.
      class EncryptionNotConfigured < Error; end

      # Raised when a provider is disabled.
      class ProviderDisabled < Error; end

      # Raised when a model is disabled.
      class ModelDisabled < Error; end

      # Raised when a capability is disabled.
      class CapabilityDisabled < Error; end

      # Raised when credentials are missing or invalid.
      class CredentialsError < Error; end

      # Raised when budget or concurrency limits are exceeded.
      class BudgetExceeded < Error; end

      # Raised when the AI system is disabled.
      class SystemDisabled < Error; end

      # Raised when store AI is disabled.
      class StoreDisabled < Error; end

      # Raised when output validation fails.
      class OutputValidationError < Error; end

      # Raised when SSRF protection triggers.
      class SSRFViolation < Error; end
    end
  end
end
