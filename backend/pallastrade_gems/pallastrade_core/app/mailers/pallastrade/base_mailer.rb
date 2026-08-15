module PallasTrade
  class BaseMailer < ActionMailer::Base
    helper PallasTrade::ImagesHelper

    default from: -> { from_address }

    def current_store
      @current_store ||= @order&.store.presence || PallasTrade::Store.current || PallasTrade::Store.default
    end

    helper_method :current_store

    # Render an email in the given locale, with the store's translation fallbacks
    # active, and restore both afterwards. Controllers set these fallbacks per
    # request via `set_fallback_locale`, but mailers run in background jobs where
    # that never happens — so without this, translatable attributes (store name,
    # product names, taxon names, …) return nil under a non-default locale and
    # leave e.g. the footer blank. Setting the fallbacks here mirrors a request,
    # so reads fall back to the store's default-locale value.
    #
    # @param store [PallasTrade::Store]
    # @param locale [String, Symbol, nil] defaults to the store's default locale
    def with_store_locale(store, locale = nil, &block)
      locale = locale.presence || store&.default_locale
      return yield if locale.blank?

      previous_fallbacks = Mobility.store_based_fallbacks
      previously_active = @_store_locale_active
      @_store_locale_active = true
      begin
        PallasTrade::Locales::SetFallbackLocaleForStore.new.call(store: store) if store
        I18n.with_locale(locale, &block)
      ensure
        @_store_locale_active = previously_active
        Mobility.store_based_fallbacks = previous_fallbacks
      end
    end

    def from_address
      current_store.mail_from_address
    end

    def reply_to_address
      current_store.customer_support_email.presence || current_store.mail_from_address
    end

    def money(amount, currency = nil)
      currency ||= current_store.default_currency
      PallasTrade::Money.new(amount, currency: currency).to_s
    end
    helper_method :money

    def frontend_available?
      PallasTrade::Core::Engine.frontend_available?
    end
    helper_method :frontend_available?

    def mail(headers = {}, &block)
      ensure_default_action_mailer_url_host(headers[:store_url])
      return unless PallasTrade::Config[:send_core_emails]

      store = current_store
      # Reply switch — only add a Reply-To header when the store allows replies.
      headers[:reply_to] ||= reply_to_address if store&.prefers_allow_email_replies?

      # DB template override — if the store has an active EmailTemplate for
      # this mailer.action, render it (with {placeholder} substitution) instead
      # of the code template. `render html:/plain:` bypasses template lookup so
      # the shared partial files are not needed here.
      render_block = block
      template = db_template_for
      if template
        @_pallastrade_email_template = template
        context = email_template_context
        render_block = proc do |format|
          format.html { render html: template.render_body(:html, context).html_safe }
          format.text { render plain: template.render_body(:text, context) }
        end
      end

      message = if @_store_locale_active
                  super(headers, &render_block)
                else
                  # Subclasses that call `mail` without wrapping their action in
                  # `with_store_locale` (e.g. Devise mailers, extensions) still get the
                  # store default locale, as `mail` applied before PallasTrade 5.6.
                  with_store_locale(current_store) { super(headers, &render_block) }
                end

      # Attach metadata so PallasTrade::EmailLogRecorder can resolve store/mailer/action.
      message.instance_variable_set(:@_pallastrade_store, store) if message
      message.instance_variable_set(:@_pallastrade_mailer, self.class.name) if message
      message.instance_variable_set(:@_pallastrade_action, action_name) if message

      # Per-store SMTP override — when the store configured its own SMTP channel
      # (Email → Settings), deliver through it instead of the platform default.
      # This is applied per-message so other stores/jobs are unaffected.
      apply_store_smtp_settings(message, store) if message

      message
    end

    # Look up an active admin-edited EmailTemplate for the current mailer action
    # (key = "order.confirm_email", "shipment.shipped_email", ...).
    # @return [PallasTrade::EmailTemplate, nil]
    def db_template_for
      store = current_store
      return nil if store.nil?
      return nil if action_name.blank?

      mailer_name = self.class.name.demodulize.sub(/Mailer\z/, '').underscore
      key = "#{mailer_name}.#{action_name}"
      store.email_templates.active.find_by(key: key)
    end

    # Placeholder substitution context for DB templates. Subclasses override to
    # expose @order/@shipment/... values as {placeholder_name} → value pairs.
    def email_template_context
      {}
    end
    helper_method :email_template_context

    # @deprecated Each mailer action now wraps its body in {#with_store_locale},
    #   which also activates the store's translation fallbacks and restores the
    #   previous locale afterwards. This method mutates `I18n.locale` for the rest
    #   of the thread without restoring it. Will be removed in PallasTrade 6.0.
    def set_email_locale
      PallasTrade::Deprecation.warn(
        'PallasTrade::BaseMailer#set_email_locale is deprecated and will be removed in PallasTrade 6.0. ' \
        'Wrap the mailer action body in `with_store_locale(store, locale) { ... }` instead.'
      )
      locale = @order&.locale.presence || @order&.store&.default_locale || current_store&.default_locale
      I18n.locale = locale if locale.present?
    end

    protected

    # The "<store> <subject> #<number>" subject line shared by customer-facing
    # order emails, with the optional [RESEND] prefix.
    def order_email_subject(store, subject, number, resend: false)
      "#{resend ? "[#{PallasTrade.t(:resend).upcase}] " : ''}#{store.name} #{subject} ##{number}"
    end

    # URI-based merge preserves existing query params and fragments so the token
    # doesn't get swallowed by a `#section` or clobber an existing `?source=`.
    def append_token(url, token)
      uri = URI.parse(url.to_s)
      params = URI.decode_www_form(uri.query || '')
      params << ['token', token.to_s]
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      separator = url.include?('?') ? '&' : '?'
      "#{url}#{separator}token=#{CGI.escape(token.to_s)}"
    end

    private

    # this ensures that ActionMailer::Base.default_url_options[:host] is always set
    # this is only a fail-safe solution if developer didn't set this in environment files
    # http://guides.rubyonrails.org/action_mailer_basics.html#generating-urls-in-action-mailer-views
    def ensure_default_action_mailer_url_host(store_url = nil)
      host_url = store_url.presence || current_store.try(:storefront_url)

      return if host_url.blank?

      ActionMailer::Base.default_url_options ||= {}
      ActionMailer::Base.default_url_options[:host] = host_url
    end

    # Route this message through the store's own SMTP channel when one is
    # configured (Email → Settings → SMTP). Per-message delivery method keeps
    # the override scoped to this message only.
    def apply_store_smtp_settings(message, store)
      settings = store_smtp_settings(store)
      return if settings.blank?

      message.delivery_method(:smtp, settings)
    rescue StandardError => e
      Rails.logger.warn("[mailer] store SMTP override failed, using default: #{e.message}")
    end

    # Build SMTP settings from the store's email preferences. Returns nil when
    # the store did not opt into its own SMTP channel (host blank = disabled).
    def store_smtp_settings(store)
      return nil unless store
      return nil if store.preferred_smtp_host.blank?

      settings = {
        address: store.preferred_smtp_host,
        port: store.preferred_smtp_port.to_i,
        authentication: store.preferred_smtp_authentication.presence&.to_sym,
        enable_starttls_auto: true
      }
      settings[:user_name] = store.preferred_smtp_user if store.preferred_smtp_user.present?
      settings[:password] = store.preferred_smtp_password if store.preferred_smtp_password.present?
      settings
    end
  end
end
