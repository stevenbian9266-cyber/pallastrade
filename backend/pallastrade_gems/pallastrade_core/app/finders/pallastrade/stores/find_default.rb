module PallasTrade
  module Stores
    class FindDefault
      def initialize(scope: nil, url: nil)
        @scope = scope || PallasTrade::Store
      end

      def execute
        store = @scope.where(default: true).first || @scope.first
        return if store.nil?

        PallasTrade::Current.store = store
        store
      end
    end
  end
end
