module PallasTrade
  module Imports
    # Shared base for every job in the imports pipeline.
    #
    # The narrow transient-error retry policy is inherited from `PallasTrade::BaseJob`;
    # we only override the queue here. Per-row business errors are caught inside
    # `PallasTrade::ImportRow#process!` and converted to `row.fail!`, so they never
    # bubble up to the job layer. Subclasses may extend the retry list (e.g.
    # `CreateCategoriesJob` adds `RecordNotUnique` to recover from concurrent
    # taxon creation races).
    class BaseJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.imports
    end
  end
end
