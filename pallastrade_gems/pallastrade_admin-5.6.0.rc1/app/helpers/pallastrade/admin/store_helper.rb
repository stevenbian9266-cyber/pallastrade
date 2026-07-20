module PallasTrade
  module Admin
    module StoreHelper
      include LocaleHelper

      def weight_units(store = nil)
        store ||= current_store

        if store.metric_unit_system?
          [
            [PallasTrade.t('weight_units.kilogram'), 'kg'],
            [PallasTrade.t('weight_units.gram'), 'g']
          ]
        else
          [
            [PallasTrade.t('weight_units.pound'), 'lb'],
            [PallasTrade.t('weight_units.ounce'), 'oz']
          ]
        end
      end

      def dimension_units(store = nil)
        store ||= current_store

        if store.metric_unit_system?
          [
            [PallasTrade.t('dimension_units.centimeter'), 'cm'],
            [PallasTrade.t('dimension_units.millimeter'), 'mm']
          ]
        else
          [
            [PallasTrade.t('dimension_units.inch'), 'in'],
            [PallasTrade.t('dimension_units.foot'), 'ft']
          ]
        end
      end

      def unit_systems
        [
          [PallasTrade.t('unit_systems.metric_system'), 'metric'],
          [PallasTrade.t('unit_systems.imperial_system'), 'imperial']
        ]
      end
    end
  end
end
