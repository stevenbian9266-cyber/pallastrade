# frozen_string_literal: true

# AI module namespace 鈥?shared concerns and base classes.
module PallasTrade
  module AI
    # Base class for all AI models. Uses the standard PallasTrade base class
    # and isolates table names under `pallastrade_ai_` prefix.
    class BaseModel < PallasTrade.base_class
      self.abstract_class = true
      self.table_name_prefix = 'pallastrade_ai_'
    end
  end
end
