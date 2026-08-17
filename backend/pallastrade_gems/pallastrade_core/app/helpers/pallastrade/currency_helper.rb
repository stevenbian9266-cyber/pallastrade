module PallasTrade
  module CurrencyHelper
    # Returns the list of all currencies as options for a select field.
    # By default the value is the default currency of the default store.
    # @param selected_value [String] the selected value
    # @return [String] the options for a select field
    def currency_options(selected_value = nil)
      selected_value ||= PallasTrade::Store.default.default_currency
      options_from_collection_for_select(all_currency_options, :last, :first, selected_value)
    end

    # Returns [label, iso_code] pairs for every ISO 4217 currency — the single
    # source for both single and multi currency selects (markets form, store
    # create form, …). Label format: "USD — United States Dollar".
    # @return [Array<Array(String, String)>]
    def all_currency_options
      @all_currency_options ||= ::Money::Currency.table.map do |_code, details|
        currency_presentation(details[:iso_code])
      end
    end

    # Returns the list of supported currencies for the current store as options for a select field.
    # @return [String] the options for a select field
    def supported_currency_options
      return if current_store.nil?

      @supported_currency_options ||= current_store.supported_currencies_list.map(&:iso_code).map { |currency| currency_presentation(currency) }
    end

    def should_render_currency_dropdown?
      return false if current_store.nil?

      current_store.supported_currencies_list.size > 1
    end

    # Returns the currency symbol for the given currency.
    # @param currency [String] the currency ISO code
    # @return [String] the currency symbol
    def currency_symbol(currency)
      ::Money::Currency.find(currency).symbol
    end

    # @param currency [String] the currency ISO code
    # @return [Array] the currency presentation and ISO code
    def currency_presentation(currency)
      [PallasTrade::Currency.new(code: currency).label, currency]
    end

    def currency_money(currency = current_currency)
      ::Money::Currency.find(currency)
    end
  end
end
