# frozen_string_literal: true

module PallasTrade
  module AI
    module Middleware
      # Faraday middleware to prevent Server-Side Request Forgery (SSRF).
      # Blocks requests to loopback, link-local, private network, and metadata IPs.
      # Validates destination after DNS resolution to prevent DNS rebinding.
      class SsrfProtection < Faraday::Middleware
        BLOCKED_IPS = [
          IPAddr.new('127.0.0.0/8'),      # Loopback
          IPAddr.new('10.0.0.0/8'),       # Private
          IPAddr.new('172.16.0.0/12'),    # Private
          IPAddr.new('192.168.0.0/16'),   # Private
          IPAddr.new('169.254.0.0/16'),   # Link-local
          IPAddr.new('0.0.0.0/8'),        # Current network
          IPAddr.new('::1'),              # IPv6 loopback
          IPAddr.new('fc00::/7'),         # IPv6 unique local
          IPAddr.new('fe80::/10')         # IPv6 link-local
        ].freeze

        def call(env)
          url = env.url
          validate_url_scheme!(url)
          validate_url_host!(url)

          @app.call(env)
        end

        private

        def validate_url_scheme!(url)
          unless url.scheme == 'https'
            raise PallasTrade::AI::Errors::SSRFViolation,
              "Only HTTPS is allowed for AI provider connections. Got: #{url.scheme}"
          end
        end

        def validate_url_host!(url)
          host = url.hostname
          raise PallasTrade::AI::Errors::SSRFViolation, 'No hostname in URL' unless host

          # Resolve the hostname and validate the IP
          ips = Resolv.getaddresses(host)
          ips.each do |ip_str|
            ip = IPAddr.new(ip_str)
            if BLOCKED_IPS.any? { |blocked| blocked.include?(ip) }
              raise PallasTrade::AI::Errors::SSRFViolation,
                "Connection to #{host} (#{ip_str}) blocked: private/loopback IP range"
            end
          end
        rescue IPAddr::InvalidAddressError
          raise PallasTrade::AI::Errors::SSRFViolation, "Invalid IP address for #{host}"
        end
      end
    end
  end
end
