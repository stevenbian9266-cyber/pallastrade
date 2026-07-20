# frozen_string_literal: true

module PallasTrade
  module Admin
    module StorefrontHelper
      STOREFRONT_REPOSITORY_URL = 'https://github.com/spree/storefront'

      # Builds the Vercel deploy-button URL for the storefront starter, prefilled
      # with the store's API URL and publishable key (both non-secret), and
      # redirecting back to the admin storefront page after a successful deploy
      # so the deployed domain can be added as an allowed origin.
      #
      # @param store [PallasTrade::Store]
      # @param api_key [PallasTrade::ApiKey] an active publishable key
      # @return [String]
      def vercel_deploy_url(store, api_key)
        query = {
          'repository-url' => STOREFRONT_REPOSITORY_URL,
          'project-name' => "#{store.code}-storefront",
          'repository-name' => "#{store.code}-storefront",
          'env' => 'pallastrade_API_URL,PALLASTRADE_PUBLISHABLE_KEY',
          'envDefaults' => {
            'pallastrade_API_URL' => store.formatted_url,
            'pallastrade_PUBLISHABLE_KEY' => api_key.token
          }.to_json,
          'envDescription' => PallasTrade.t('admin.storefront_setup.env_description'),
          'envLink' => "#{STOREFRONT_REPOSITORY_URL}#readme",
          'redirect-url' => PallasTrade.admin_storefront_url
        }

        "https://vercel.com/new/clone?#{query.to_query}"
      end

      # True when the store's public URL points at a loopback host, which
      # Vercel's build servers cannot reach.
      #
      # @param store [PallasTrade::Store]
      # @return [Boolean]
      def store_url_loopback?(store = current_store)
        PallasTrade::AllowedOrigin::LOOPBACK_HOSTS.include?(
          PallasTrade::AllowedOrigin.parse_origin(store.formatted_url)&.dig(:host)
        )
      end
    end
  end
end
