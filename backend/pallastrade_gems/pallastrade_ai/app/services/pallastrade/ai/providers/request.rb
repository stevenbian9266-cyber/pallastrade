# frozen_string_literal: true

module PallasTrade
  module AI
    module Providers
      # Standard request object passed to provider adapters.
      Request = Struct.new(
        :messages,
        :model,
        :system_instructions,
        :response_schema,
        :parameters,
        :privacy_identifier,
        :idempotency_key,
        :stream_callback,
        keyword_init: true
      )
    end
  end
end
