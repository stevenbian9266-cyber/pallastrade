# frozen_string_literal: true

module PallasTradeAI
  class Configuration
    # System-level kill switch. When false, ALL AI requests are blocked
    # regardless of store/provider/model/capability settings.
    # Controlled via ENV['PALLASTRADE_AI_ENABLED'].
    # @return [Boolean]
    def system_enabled?
      ENV.fetch('PALLASTRADE_AI_ENABLED', 'false') == 'true'
    end

    # Default content logging mode for new stores.
    # @return [String] 'none' | 'metadata' | 'encrypted'
    def default_content_logging_mode
      'none'
    end

    # Default run retention in days.
    # @return [Integer]
    def default_run_retention_days
      30
    end

    # Maximum response body size in bytes from external providers.
    # @return [Integer]
    def max_response_size
      10 * 1024 * 1024 # 10 MB
    end

    # Default open timeout for Faraday connections (seconds).
    # @return [Integer]
    def default_open_timeout_seconds
      5
    end

    # Default read timeout for Faraday connections (seconds).
    # @return [Integer]
    def default_read_timeout_seconds
      60
    end

    # Default max retries for transient failures.
    # @return [Integer]
    def default_max_retries
      2
    end

    # Default per-provider concurrency limit.
    # @return [Integer]
    def default_concurrency_limit
      5
    end
  end
end
