module PallasTrade
  module Stock
    module Splitter
      class Backordered < PallasTrade::Stock::Splitter::Base
        def split(packages)
          split_packages = []

          packages.each do |package|
            split_packages << build_package(package.on_hand) unless package.on_hand.empty?

            split_packages << build_package(package.backordered) unless package.backordered.empty?
          end

          return_next(split_packages)
        end
      end
    end
  end
end
