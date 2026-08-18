module PallasTrade
  module Authentication
    # Verifies third-party OAuth tokens against the provider's public endpoints.
    #
    # Kept as a small, dependency-injectable service so strategies stay thin and
    # specs can stub the HTTP layer without WebMock. Each method returns a Hash
    # of verified profile claims (`:provider_uid`, `:email`, `:first_name`,
    # `:last_name`, `:email_verified`) or `nil` when verification fails.
    #
    # No new gem: Google uses the public `tokeninfo` endpoint and Facebook uses
    # the Graph API (debug_token + me), both via Net::HTTP.
    class OAuthTokenValidator
      GOOGLE_TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo'.freeze
      FACEBOOK_GRAPH_URL = 'https://graph.facebook.com'.freeze

      # @param google_client_id [String, nil] expected audience for Google ID tokens
      # @param facebook_app_id [String, nil]
      # @param facebook_app_secret [String, nil]
      def initialize(google_client_id: nil, facebook_app_id: nil, facebook_app_secret: nil)
        @google_client_id = google_client_id
        @facebook_app_id = facebook_app_id
        @facebook_app_secret = facebook_app_secret
      end

      # Verify a Google ID token and return normalized profile claims.
      # @param id_token [String]
      # @return [Hash, nil]
      def google(id_token)
        return nil if id_token.blank? || @google_client_id.blank?

        payload = get_json(GOOGLE_TOKENINFO_URL, id_token: id_token)
        return nil unless payload.is_a?(Hash)

        # tokeninfo returns the token audience under "aud"; it must match our
        # OAuth client id or the token was minted for a different application.
        return nil unless payload['aud'].to_s == @google_client_id.to_s
        # exp is Unix seconds; reject expired tokens explicitly (tokeninfo also
        # errors on expired tokens, but we stay defensive).
        return nil if payload['exp'].present? && payload['exp'].to_i < Time.now.to_i
        return nil unless payload['email'].present?

        {
          provider_uid: payload['sub'],
          email: payload['email'],
          first_name: payload['given_name'],
          last_name: payload['family_name'],
          email_verified: payload['email_verified'] == 'true' || payload['email_verified'] == true
        }
      rescue StandardError => e
        Rails.logger.warn "Google OAuth token verification failed: #{e.message}"
        nil
      end

      # Verify a Facebook user access token and return normalized profile claims.
      # Uses an app token to call debug_token, then fetches the profile via /me.
      # @param access_token [String]
      # @return [Hash, nil]
      def facebook(access_token)
        return nil if access_token.blank? || @facebook_app_id.blank? || @facebook_app_secret.blank?

        app_token = "#{@facebook_app_id}|#{@facebook_app_secret}"

        # 1. Verify the token belongs to this app.
        debug = get_json("#{FACEBOOK_GRAPH_URL}/debug_token", input_token: access_token, access_token: app_token)
        data = debug.is_a?(Hash) && debug['data']
        return nil unless data.is_a?(Hash) && data['is_valid'] == true
        return nil unless data['app_id'].to_s == @facebook_app_id.to_s
        return nil if data['type'] != 'USER'

        # 2. Fetch the profile (id/name/email).
        profile = get_json(
          "#{FACEBOOK_GRAPH_URL}/me",
          fields: 'id,name,email',
          access_token: access_token
        )
        return nil unless profile.is_a?(Hash) && profile['id'].present?

        email = profile['email']
        # Only bind by email when Facebook actually returned a verified email.
        return nil if email.blank?

        name = profile['name'].to_s.split(' ', 2)
        {
          provider_uid: profile['id'],
          email: email,
          first_name: name[0],
          last_name: name[1],
          email_verified: true
        }
      rescue StandardError => e
        Rails.logger.warn "Facebook OAuth token verification failed: #{e.message}"
        nil
      end

      private

      # GET with query params, returns parsed JSON or nil on non-200.
      def get_json(url, **query)
        uri = URI(url)
        uri.query = URI.encode_www_form(query) unless query.empty?
        response = Net::HTTP.get_response(uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.warn "OAuth validator HTTP request failed (#{url}): #{e.message}"
        nil
      end
    end
  end
end
