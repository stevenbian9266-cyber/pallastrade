require "active_support/core_ext/integer/time"

Rails.application.configure do
  # When SMTP_HOST is set deliver via SMTP.
  # Otherwise use Letter Opener to preview emails in the browser.
  if ENV["SMTP_HOST"].present?
    config.action_mailer.delivery_method = :smtp
    smtp_settings = {
      address:              ENV["SMTP_HOST"],
      port:                 ENV.fetch("SMTP_PORT", 1025).to_i,
      enable_starttls_auto: true
    }
    # Only request SMTP-AUTH when credentials are provided. Local mail catchers
    # (Mailpit, MailHog) accept anonymous delivery; requesting auth with a nil
    # user raises "SMTP-AUTH requested but missing user name" before connecting.
    if ENV["SMTP_USERNAME"].present?
      smtp_settings[:user_name]      = ENV["SMTP_USERNAME"]
      smtp_settings[:password]       = ENV["SMTP_PASSWORD"]
      smtp_settings[:authentication] = :plain
    end
    config.action_mailer.smtp_settings = smtp_settings
    config.action_mailer.default_options = { from: ENV["SMTP_FROM_ADDRESS"] } if ENV["SMTP_FROM_ADDRESS"].present?
    config.action_mailer.raise_delivery_errors = true
  else
    config.action_mailer.delivery_method = :letter_opener
    config.action_mailer.raise_delivery_errors = false
  end
  config.action_mailer.perform_deliveries = true

  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # 事件驱动文件监听（listen gem）。默认轮询 FileUpdateChecker 在
  # Docker Desktop Windows bind mount 上每次请求 stat 大量文件 → 10-20s/请求。
  # listen（inotify）改为事件驱动，大幅降低请求延迟。
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false

  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  # Disabled in dev for performance — verbose query logs add significant overhead.
  config.active_record.verbose_query_logs = false

  # Append comments with runtime information tags to SQL queries in logs.
  # Disabled: source location tracking adds measurable per-query latency.
  config.active_record.query_log_tags_enabled = false

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = false

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = false

  # Reduce log verbosity in dev for faster request processing.
  config.log_level = :info

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Annotate rendered view with file names — disabled for performance.
  config.action_view.annotate_rendered_view_with_filenames = false

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
