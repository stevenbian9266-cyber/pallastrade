module SpreeStripe
  class BaseJob < PallasTrade::BaseJob
    queue_as SpreeStripe.queue
  end
end
