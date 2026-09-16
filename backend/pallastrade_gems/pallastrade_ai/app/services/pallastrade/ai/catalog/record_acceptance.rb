# frozen_string_literal: true

module PallasTrade
  module AI
    module Catalog
      # Records what the merchant did with a generated draft
      # (PRD-20260916-catalog-ai-acceptance-audit).
      #
      # The generation side was already auditable — every call writes an
      # `AI::Run` and an `AI::Artifact`. The acceptance side was not: the admin's
      # ai-assist controller only wrote the draft into the form (or threw it
      # away), so "how often is the AI draft actually used?" had no answer.
      #
      # Kept as a service so the rules live in one place — the Run list and any
      # future report read the same two fields.
      class RecordAcceptance
        # Deliberately *not* `prepend PallasTrade::ServiceModule::Base`: that
        # wrapper swaps the return value for its own generic `Result`
        # (success/value/error), which would hide `status` and `error_code`
        # from the caller — the endpoint needs those to answer 422 vs 200.
        def self.call(...)
          new.call(...)
        end

        # @!attribute [r] status
        #   @return [Symbol] :recorded / :unchanged / :invalid_state
        # @!attribute [r] run
        #   @return [PallasTrade::AI::Run]
        # @!attribute [r] error_code
        #   @return [String, nil] stable code for the caller's JSON response
        Result = Struct.new(:status, :run, :error_code, keyword_init: true) do
          def success?
            %i[recorded unchanged].include?(status)
          end

          def changed?
            status == :recorded
          end
        end

        # @param run [PallasTrade::AI::Run] already store-scoped by the caller
        # @param state [String, Symbol] accepted / discarded
        # @return [Result]
        def call(run:, state:)
          state = state.to_s

          unless PallasTrade::AI::Run::ACCEPTANCE_STATES.include?(state)
            return Result.new(status: :invalid_state, run: run, error_code: 'invalid_acceptance_state')
          end

          changed = run.record_acceptance!(state)

          Result.new(status: changed ? :recorded : :unchanged, run: run, error_code: nil)
        end
      end
    end
  end
end
