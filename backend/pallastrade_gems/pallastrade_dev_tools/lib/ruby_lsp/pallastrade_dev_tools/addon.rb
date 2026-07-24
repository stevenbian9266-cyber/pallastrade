# frozen_string_literal: true

require "ruby_lsp/addon"

module RubyLsp
  module PallasTradeDevTools
    class Addon < ::RubyLsp::Addon
      VERSION = "0.1.0"

      PALLASTRADE_GEMS = %w[
        pallastrade_core
        pallastrade_api
        pallastrade_admin
        pallastrade_storefront
        pallastrade_emails
      ].freeze

      def activate(global_state, outgoing_queue)
        @global_state = global_state
        @outgoing_queue = outgoing_queue
        @index = global_state.index

        # Index PallasTrade app directories in a background thread
        Thread.new { index_pallastrade_app_directories }
      end

      def deactivate; end

      def name
        "Ruby LSP PallasTrade"
      end

      def version
        VERSION
      end

      private

      def log(message)
        return unless @outgoing_queue

        @outgoing_queue << RubyLsp::Notification.window_log_message(message)
      end

      def index_pallastrade_app_directories
        log("[PallasTrade] Starting to index app/ directories from PallasTrade gems...")

        indexed_count = 0

        PALLASTRADE_GEMS.each do |gem_name|
          count = index_gem_app_directory(gem_name)
          indexed_count += count if count
        end

        log("[PallasTrade] Finished indexing #{indexed_count} files from PallasTrade app/ directories")
      rescue => e
        log("[PallasTrade] Error during indexing: #{e.message}")
      end

      def index_gem_app_directory(gem_name)
        spec = Gem::Specification.find_by_name(gem_name)
        app_path = File.join(spec.full_gem_path, "app")

        return 0 unless File.directory?(app_path)

        files = Dir.glob(File.join(app_path, "**", "*.rb"))
        log("[PallasTrade] Indexing #{files.size} files from #{gem_name}/app/")

        files.each do |file_path|
          uri = URI::Generic.from_path(path: file_path)
          @index.index_file(uri, collect_comments: true)
        end

        files.size
      rescue Gem::MissingSpecError
        log("[PallasTrade] Gem #{gem_name} not found, skipping")
        0
      rescue => e
        log("[PallasTrade] Error indexing #{gem_name}: #{e.message}")
        0
      end
    end
  end
end
