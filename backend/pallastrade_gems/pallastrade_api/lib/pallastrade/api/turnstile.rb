# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module PallasTrade
  module Api
    # Cloudflare Turnstile server-side verification.
    #
    # Used by the Store API registration endpoint to prove the visitor is a human.
    #
    #   PallasTrade::Api::Turnstile.configured?          # => TURNSTILE_SECRET_KEY present?
    #   PallasTrade::Api::Turnstile.verify(token, remote_ip: '1.2.3.4')  # => true/false
    #
    # Security contract:
    #   * The SECRET key is read ONLY from ENV['TURNSTILE_SECRET_KEY'] — never from
    #     code, repo, or config files that get committed.
    #   * Fail-closed: network errors, timeouts, non-2xx responses and malformed
    #     bodies all return +false+ (never bypass verification on uncertainty).
    #   * The public site key lives in the storefront build env (NEXT_PUBLIC_*)
    #     and is intentionally NOT needed on the server.
    class Turnstile
      VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify'.freeze
      TIMEOUT_SECONDS = 5

      class << self
        # Whether the server-side secret key is configured.
        def configured?
          secret_key.present?
        end

        # @return [String] the configured secret key ('' when unset)
        def secret_key
          ENV['TURNSTILE_SECRET_KEY'].to_s.strip
        end

        # Verify a Turnstile response token against Cloudflare.
        #
        # @param response_token [String] the `cf-turnstile-response` value from the widget
        # @param remote_ip [String, nil] optional client IP for enhanced validation
        # @return [Boolean, nil] +true+ when Cloudflare reports success; +false+ when
        #   Cloudflare explicitly rejects the token; +nil+ when verification is
        #   *unable to run* (not configured, network error, timeout, or an upstream
        #   anomaly) — callers may decide how to degrade (e.g. fall back open with
        #   logging for regions where Cloudflare is unreachable).
        def verify(response_token, remote_ip: nil)
          new(response_token, remote_ip: remote_ip).verify
        end
      end

      attr_reader :response_token, :remote_ip

      def initialize(response_token, remote_ip: nil)
        @response_token = response_token.to_s
        @remote_ip = remote_ip
      end

      def verify
        # 未配置 secret → 无法验证（nil，调用方按未启用处理）
        return nil unless self.class.configured?
        # token 缺失 → 明确视为未通过
        return false if response_token.blank?

        uri = URI(VERIFY_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = TIMEOUT_SECONDS
        http.read_timeout = TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri)
        request.set_form_data(verification_params)

        response = http.request(request)
        # 非 2xx（网关错误/上游异常）→ 无法验证（nil），区别于 Cloudflare 明确拒绝
        return nil unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        body['success'] == true
      rescue StandardError
        # 网络错误 / 超时 / 响应解析失败 → 无法验证（nil）
        # 注：国内服务器访问 challenges.cloudflare.com 常被网络干扰（TCP/TLS 通但
        # HTTPS 请求无响应），此处返回 nil 让调用方决定降级策略。
        nil
      end

      private

      def verification_params
        params = { secret: self.class.secret_key, response: response_token }
        params[:remoteip] = remote_ip if remote_ip.present?
        params
      end
    end
  end
end
