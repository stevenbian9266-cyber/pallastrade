module PallasTradeStripe
  class BaseJob < PallasTrade::BaseJob
    queue_as PallasTradeStripe.queue
  end
end
