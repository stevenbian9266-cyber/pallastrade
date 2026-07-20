module PallasTradeAdyen
  class BaseJob < PallasTrade::BaseJob
    queue_as PallasTradeAdyen.queue
  end
end
