# frozen_string_literal: true

module PallasTrade
  module AI
    # Store-level AI settings. One per store.
    # Controls the store AI master switch, budget limits, retention, and logging mode.
    class Setting < BaseModel
      self.table_name = 'pallastrade_ai_settings'
      include PallasTrade::SingleStoreResource

      belongs_to :store, class_name: 'PallasTrade::Store'
      belongs_to :default_model, class_name: 'PallasTrade::AI::Model', optional: true

      validates :store, presence: true, uniqueness: true
      validates :content_logging_mode, inclusion: { in: %w[none metadata encrypted] }
      validates :run_retention_days, numericality: { greater_than: 0, less_than_or_equal_to: 365 }
      validates :daily_request_limit, numericality: { greater_than: 0 }, allow_nil: true
      validates :daily_input_token_limit, numericality: { greater_than: 0 }, allow_nil: true
      validates :daily_output_token_limit, numericality: { greater_than: 0 }, allow_nil: true
      validates :daily_cost_limit, numericality: { greater_than: 0 }, allow_nil: true

      # The default model must belong to the same store.
      validate :default_model_belongs_to_store, if: -> { default_model.present? }

      # Quick check if the store-level AI switch is on.
      def enabled?
        active?
      end

      private

      def default_model_belongs_to_store
        return if default_model.store_id == store_id

        errors.add(:default_model, :must_belong_to_same_store)
      end
    end
  end
end
