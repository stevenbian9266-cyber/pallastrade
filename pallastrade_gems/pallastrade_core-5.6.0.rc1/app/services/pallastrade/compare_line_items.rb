# This class should be refactored
module PallasTrade
  class CompareLineItems
    prepend PallasTrade::ServiceModule::Base

    def call(order:, line_item:, options: {}, comparison_hooks: nil)
      comparison_hooks ||= PallasTrade.line_item_comparison_hooks

      legacy_part = comparison_hooks.all? do |hook|
        order.send(hook, line_item, options)
      end

      success(legacy_part && compare(line_item, options))
    end

    private

    # write your custom logic here
    def compare(_line_item, _options)
      true
    end
  end
end
