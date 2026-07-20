module SpreeStripe
  module PaymentSourceDecorator
    def self.prepended(base)
      base.attr_accessor :imported
    end
  end
end

PallasTrade::PaymentSource.prepend(SpreeStripe::PaymentSourceDecorator)
