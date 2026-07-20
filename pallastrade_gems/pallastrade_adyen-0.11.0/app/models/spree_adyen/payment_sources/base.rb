module SpreeAdyen
  module PaymentSources
    class Base < ::PallasTrade::PaymentSource
      self.abstract_class = true
    end
  end
end
