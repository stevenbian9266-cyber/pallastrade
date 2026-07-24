module PallasTrade
  module Reports
    class GenerateJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.reports

      # `Report#generate` is not retry-safe: each call re-attaches a new ActiveStorage
      # blob (leaving the prior one orphaned) and re-enqueues the completion email.
      # Opt out of the parent's retry policy so transient errors fail fast into the
      # dead queue for operator review rather than producing duplicate side effects.
      retry_on ActiveRecord::Deadlocked,
               ActiveRecord::LockWaitTimeout,
               ActiveRecord::ConnectionNotEstablished,
               ActiveRecord::ConnectionFailed,
               ActiveRecord::RecordNotFound,
               attempts: 1

      def perform(report_id)
        report = PallasTrade::Report.find_by_prefix_id!(report_id)
        report.generate
      end
    end
  end
end
