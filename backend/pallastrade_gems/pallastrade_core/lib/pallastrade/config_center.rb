# frozen_string_literal: true

module PallasTrade
  # Unified Config Center — the application-facing read layer for managed
  # parameters (see {PallasTrade::ConfigItem}).
  #
  # Read semantics (single source of truth = the Config Center):
  #   * +get(key)+          → ConfigItem value → ENV[env_key] → default
  #   * +fetch_secret(key)+ → ConfigItem plaintext (encrypted lane) → ENV[env_key]
  #
  # +sync_env!+ copies configured items into +ENV+ at boot so legacy +ENV[...]+
  # read sites (e.g. `config/environments/production.rb` OSS selection) work
  # unchanged. The Config Center takes precedence over +.env+ by default;
  # see +env_precedence:+ for the compatibility switch.
  #
  # Values are cached in-process / Rails.cache with a short TTL plus explicit
  # invalidation on writes, so admin updates take effect without a restart.
  module ConfigCenter
    CACHE_PREFIX = 'pallastrade/config_center'
    CACHE_TTL = 60 # seconds — safety net; explicit invalidate! on writes

    module_function

    # @param key [String] e.g. "oss.access_key_id"
    # @param default [Object] fallback when neither ConfigItem nor ENV has a value
    # @param store [PallasTrade::Store, nil] defaults to Store.current
    # @return [Object, nil] typed value from the Config Center, ENV string, or default
    def get(key, default: nil, store: nil)
      item = find_item(key, store)
      return item.typed_value if item&.configured?

      env = ENV[env_key(key)]
      env.present? ? env : default
    end

    # Server-internal plaintext read for secret items. Never exposed via API.
    # Falls back to ENV when the Config Center has no value for this key.
    # @return [String, nil]
    def fetch_secret(key, store: nil)
      item = find_item(key, store)
      return item.raw_value if item&.configured?

      ENV[env_key(key)]
    end

    # Copies all configured items into +ENV+ (Config Center precedence unless
    # +env_precedence+ is given). Called from the host-app boot initializer.
    # @param store [PallasTrade::Store, nil] restrict to one store when given
    # @param env_precedence [Boolean] keep existing ENV values when true
    def sync_env!(store: nil, env_precedence: false)
      items = store ? store.config_items : PallasTrade::ConfigItem.all
      items.find_each do |item|
        next unless item.configured?

        key = item.env_key
        if env_precedence
          ENV[key] ||= item.raw_value.to_s
        else
          ENV[key] = item.raw_value.to_s
        end
      end
    end

    # Invalidates cached lookups. +key+ nil clears the whole Config Center cache
    # (config volume is small — safe and simple).
    def invalidate!(_key = nil)
      Rails.cache.delete_matched("#{CACHE_PREFIX}:*")
    end

    # "oss.access_key_id" → "OSS_ACCESS_KEY_ID"
    def env_key(key)
      key.to_s.upcase.tr('.', '_')
    end

    # @api private
    def find_item(key, store)
      store ||= PallasTrade::Store.current
      return nil unless store

      Rails.cache.fetch("#{CACHE_PREFIX}:#{store.id}:#{key}", expires_in: CACHE_TTL) do
        store.config_items.for_key(key).first
      end
    end
  end
end
