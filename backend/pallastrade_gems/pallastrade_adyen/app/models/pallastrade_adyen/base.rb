module PallasTradeAdyen
  class Base < PallasTrade.base_class
    self.abstract_class = true
    self.table_name_prefix = 'pallastrade_adyen_'
  end
end
