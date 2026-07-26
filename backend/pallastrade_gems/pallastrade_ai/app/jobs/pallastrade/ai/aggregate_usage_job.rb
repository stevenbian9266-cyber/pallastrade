# frozen_string_literal: true

module PallasTrade
  module AI
    # Aggregates daily AI usage metrics for reporting.
    class AggregateUsageJob < ActiveJob::Base
      queue_as { PallasTradeAI.batch_queue }

      def perform(store_id: nil, date: Date.yesterday)
        scope = PallasTrade::AI::Run.where(created_at: date.beginning_of_day..date.end_of_day)
        scope = scope.where(store_id: store_id) if store_id

        aggregated = scope.group(:store_id, :capability_key, :provider_type, :model_id)
                          .pluck(
                            :store_id, :capability_key, :provider_type, :model_id,
                            Arel.sql('COUNT(*)'),
                            Arel.sql('SUM(input_tokens)'),
                            Arel.sql('SUM(output_tokens)'),
                            Arel.sql('SUM(estimated_cost)'),
                            Arel.sql("COUNT(*) FILTER (WHERE status = 'succeeded')"),
                            Arel.sql("COUNT(*) FILTER (WHERE status = 'failed')"),
                            Arel.sql("COUNT(*) FILTER (WHERE status = 'skipped')")
                          )

        aggregated.each do |row|
          store_id_val, cap_key, prov_type, model_id, total, in_tok, out_tok, cost, succ, fail, skip = row

          # Write to daily usage summary table (to be created in a future migration
          # when usage data grows enough to warrant pre-aggregation).
          # For now, usage is computed directly from the runs table.
          Rails.logger.info(
            "[PallasTrade AI] Daily usage: store=#{store_id_val} cap=#{cap_key} " \
            "provider=#{prov_type} model=#{model_id} total=#{total} " \
            "success=#{succ} failed=#{fail} skipped=#{skip} " \
            "tokens_in=#{in_tok} tokens_out=#{out_tok} cost=#{cost}"
          )
        end
      end
    end
  end
end
