require_dependency 'pallastrade/data_feed'

module PallasTrade
  class DataFeed::Google < DataFeed
    class << self
      def label
        'Google Merchant Center Feed'
      end

      def provider_name
        'google'
      end

      def presenter_class
        PallasTrade::DataFeeds::GooglePresenter
      end
    end
  end
end
