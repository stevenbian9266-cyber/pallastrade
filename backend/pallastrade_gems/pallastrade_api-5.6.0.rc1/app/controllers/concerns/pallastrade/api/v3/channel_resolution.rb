module PallasTrade
  module Api
    module V3
      # Resolves the active PallasTrade::Channel for an API request and writes it
      # into +PallasTrade::Current.channel+ so models, scopes, and serializers can
      # read channel context without threading it through method args.
      #
      # Resolution order:
      # 1. +X-PallasTrade-Channel+ header value matched against +channels.code+ —
      #    or, if it looks like a prefixed ID (+ch_…+), against +channels.id+
      #    — scoped to the current store
      # 2. +current_store.default_channel+
      #
      # The concern is a no-op if no channel matches — callers fall back to
      # +PallasTrade::Current.channel+'s store-default behavior.
      module ChannelResolution
        extend ActiveSupport::Concern

        CHANNEL_HEADER = 'X-PallasTrade-Channel'.freeze
        LEGACY_CHANNEL_HEADER = 'X-PallasTrade-Channel'.freeze

        included do
          before_action :set_current_channel
        end

        protected

        def current_channel
          @current_channel ||= channel_from_header || PallasTrade::Current.channel
        end

        private

        # Only write to PallasTrade::Current when the header resolves a specific
        # channel. The store-default fallback is handled lazily by
        # +PallasTrade::Current.channel+ itself, which avoids one query per
        # header-less API request.
        def set_current_channel
          # Memoize so a later +current_channel+ call (e.g. the storefront gate,
          # serializer params) reuses this row instead of re-querying the header.
          @current_channel = channel_from_header
          PallasTrade::Current.channel = @current_channel if @current_channel
        end

        def channel_from_header
          value = request.headers[CHANNEL_HEADER].presence || request.headers[LEGACY_CHANNEL_HEADER].presence
          return nil if value.blank?
          return nil unless current_store

          scope = current_store.channels.active
          # Accept either a merchant-meaningful +code+ ("pos", "wholesale") or
          # the opaque prefixed ID — mirrors how Store API endpoints accept
          # either slug or prefixed ID (e.g. +products/{slug-or-id}+).
          if PallasTrade::PrefixedId.prefixed_id?(value)
            scope.find_by_prefix_id(value)
          else
            scope.find_by(code: value)
          end
        end
      end
    end
  end
end
