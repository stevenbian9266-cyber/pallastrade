module PallasTrade
  module Imports
    class Customers < PallasTrade::Import
      def row_processor_class
        PallasTrade::Imports::RowProcessors::Customer
      end
    end
  end
end
