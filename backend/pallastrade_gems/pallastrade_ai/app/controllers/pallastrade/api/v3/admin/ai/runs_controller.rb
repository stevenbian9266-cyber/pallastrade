# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET /api/v3/admin/ai/runs     鈥?list AI runs
          # GET /api/v3/admin/ai/runs/:id 鈥?show a single run
          class RunsController < BaseController
            def index
              authorize! :show, PallasTrade::AI::Run
              runs = filtered_runs.page(params[:page]).per(params[:per_page] || 25)
              render json: serialize_resources(runs)
            end

            def show
              run = PallasTrade::AI::Run.where(store: current_store).find(params[:id])
              authorize! :show, run
              render json: serialize_resource(run)
            end

            private

            def filtered_runs
              scope = PallasTrade::AI::Run.where(store: current_store).recent

              scope = scope.where(status: params[:status]) if params[:status].present?
              scope = scope.where(capability_key: params[:capability_key]) if params[:capability_key].present?
              scope = scope.where(provider_id: params[:provider_id]) if params[:provider_id].present?
              scope = scope.where(model_id: params[:model_id]) if params[:model_id].present?
              scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
              scope = scope.where(error_code: params[:error_code]) if params[:error_code].present?
              scope = scope.where(mode: params[:mode]) if params[:mode].present?

              if params[:start_date].present?
                scope = scope.where('created_at >= ?', Time.zone.parse(params[:start_date]))
              end
              if params[:end_date].present?
                scope = scope.where('created_at <= ?', Time.zone.parse(params[:end_date]))
              end

              scope
            end
          end
        end
      end
    end
  end
end
