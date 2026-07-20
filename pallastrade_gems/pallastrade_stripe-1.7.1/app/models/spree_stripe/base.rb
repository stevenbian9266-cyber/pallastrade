module SpreeStripe
  class Base < PallasTrade::Base
    self.abstract_class = true
    self.table_name_prefix = 'pallastrade_stripe_'
  end
end
