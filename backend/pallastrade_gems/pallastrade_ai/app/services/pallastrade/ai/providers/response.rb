# frozen_string_literal: true

module PallasTrade
  module AI
    module Providers
      # Standard response object returned by provider adapters.
      Response = Struct.new(
        :text,
        :structured_output,
        :provider_request_id,
        :provider_model_id,
        :finish_reason,
        :usage,
        :safe_metadata,
        :raw_response,
        keyword_init: true
      )
    end
  end
end
