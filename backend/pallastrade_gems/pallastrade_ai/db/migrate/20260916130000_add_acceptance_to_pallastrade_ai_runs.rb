# frozen_string_literal: true

# Catalog AI acceptance audit (PRD-20260916-catalog-ai-acceptance-audit):
# the generation side already records every call (status/tokens/cost), but
# nothing recorded whether the merchant *kept* the draft — so the AI acceptance
# rate was unmeasurable. `acceptance_state` is nil until the merchant decides;
# `accepted_at` is when that decision was recorded (also set on discard).
class AddAcceptanceToPallasTradeAIRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_ai_runs, :acceptance_state, :string
    add_column :pallastrade_ai_runs, :accepted_at, :datetime

    add_index :pallastrade_ai_runs, %i[store_id acceptance_state],
              name: 'idx_ai_runs_on_store_and_acceptance'
  end
end
