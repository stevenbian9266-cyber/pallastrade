# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET /api/v3/admin/ai/usage 鈥?aggregated usage summary
          class UsageController < BaseController
            def index
              authorize! :show, PallasTrade::AI::Run

              scope = PallasTrade::AI::Run.where(store: current_store)

              if params[:start_date].present?
                scope = scope.where('created_at >= ?', Time.zone.parse(params[:start_date]))
              end
              if params[:end_date].present?
                scope = scope.where('created_at <= ?', Time.zone.parse(params[:end_date]))
              end

              summary = {
                total_runs: scope.count,
                succeeded: scope.where(status: 'succeeded').count,
                failed: scope.where(status: 'failed').count,
                skipped: scope.where(status: 'skipped').count,
                total_input_tokens: scope.sum(:input_tokens),
                total_output_tokens: scope.sum(:output_tokens),
                total_reasoning_tokens: scope.sum(:reasoning_tokens),
                total_estimated_cost: scope.sum(:estimated_cost),
                avg_latency_ms: scope.where.not(latency_ms: nil).average(:latency_ms)&.to_i
              }

              # Breakdown by capability
              by_capability = scope.group(:capability_key)
                                   .pluck(:capability_key, Arel.sql('COUNT(*)'), Arel.sql('SUM(estimated_cost)'))
                                   .map do |key, count, cost|
                { capability_key: key, count: count, estimated_cost: cost }
              end

              # Breakdown by provider
              by_provider = scope.group(:provider_type)
                                 .pluck(:provider_type, Arel.sql('COUNT(*)'), Arel.sql('SUM(estimated_cost)'))
                                 .map do |type, count, cost|
                { provider_type: type, count: count, estimated_cost: cost }
              end

              render json: {
                data: {
                  summary: summary,
                  by_capability: by_capability,
                  by_provider: by_provider
                }
              }
            end
          end
        end
      end
    end
  end
end
