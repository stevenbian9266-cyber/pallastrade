# frozen_string_literal: true

module PallasTrade
  module Storage
    # Resolves the Active Storage service name from ENV (which by boot time may
    # already be enriched by the Config Center via ConfigCenter.sync_env!).
    #
    # Called twice:
    #   1. at boot (config/environments/*.rb) — DB may not be ready, ENV only;
    #   2. in config/initializers/config_center.rb (after_initialize) — after
    #      ConfigCenter.sync_env! merged Config Center values into ENV, so the
    #      final service selection reflects managed config.
    module ServiceResolver
      module_function

      def resolve
        if ENV['OSS_ACCESS_KEY_ID'].present? && ENV['OSS_SECRET_ACCESS_KEY'].present? && ENV['OSS_ENDPOINT'].present?
          :aliyun
        elsif ENV['AWS_ACCESS_KEY_ID'].present? && ENV['AWS_SECRET_ACCESS_KEY'].present?
          :amazon
        elsif ENV['CLOUDFLARE_ACCESS_KEY_ID'].present? && ENV['CLOUDFLARE_SECRET_ACCESS_KEY'].present? && ENV['CLOUDFLARE_ENDPOINT'].present?
          :cloudflare
        else
          :local
        end
      end
    end
  end
end
