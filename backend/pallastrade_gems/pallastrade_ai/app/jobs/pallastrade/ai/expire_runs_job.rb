# frozen_string_literal: true

module PallasTrade
  module AI
    # Periodically cleans up expired AI runs based on store retention policy.
    class ExpireRunsJob < ActiveJob::Base
      queue_as { PallasTradeAI.batch_queue }

      def perform
        PallasTrade::AI::Setting.find_each do |setting|
          retention_days = setting.run_retention_days || 30
          cutoff = retention_days.days.ago

          PallasTrade::AI::Run.where(store_id: setting.store_id)
                              .where('created_at < ?', cutoff)
                              .find_each(&:destroy!)
        end
      end
    end
  end
end
