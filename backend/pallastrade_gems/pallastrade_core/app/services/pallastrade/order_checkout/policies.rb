# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # Checkout 报价策略（共享只读值）。
    module Policies
      module_function

      # 报价有效期（默认 30 分钟；可用 ENV CHECKOUT_QUOTE_WINDOW_MINUTES 覆盖；
      # 不引入未注册的 PallasTrade::Config 键）。
      def quote_window
        minutes = ENV.fetch(%q{CHECKOUT_QUOTE_WINDOW_MINUTES}, 30).to_i
        minutes.minutes
      end
    end
  end
end
