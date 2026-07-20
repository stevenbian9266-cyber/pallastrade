module SpreeAdyen
  class BaseJob < PallasTrade::BaseJob
    queue_as SpreeAdyen.queue
  end
end
