module PallasTrade
  module Admin
    module TranslationsHelper
      def link_to_edit_translations(resource, options = {})
        return unless PallasTrade.translatable_resources.map(&:name).include?(resource.class.name)
        return unless can?(:update, resource)
        return unless can?(:update, :translations)

        options[:class] ||= 'dropdown-item'
        options[:data]  ||= { action: 'drawer#open', turbo_frame: :drawer }

        link_to_with_icon(
          'language',
          PallasTrade.t(:translations),
          PallasTrade.edit_admin_translation_path(resource.to_param, resource_type: resource.class.to_s),
          options
        )
      end
    end
  end
end
