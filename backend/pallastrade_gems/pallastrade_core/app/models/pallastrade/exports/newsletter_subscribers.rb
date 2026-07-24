module PallasTrade
  module Exports
    class NewsletterSubscribers < PallasTrade::Export
      def self.required_scope
        :customers
      end

      def scope_includes
        [:user, { metafields: :metafield_definition }]
      end

      def csv_headers
        PallasTrade::CSV::NewsletterSubscriberPresenter::HEADERS + metafields_headers
      end
    end
  end
end
