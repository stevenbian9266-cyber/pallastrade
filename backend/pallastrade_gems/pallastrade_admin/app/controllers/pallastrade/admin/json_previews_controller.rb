module PallasTrade
  module Admin
    class JsonPreviewsController < ResourceController
      private

      def model_class
        @model_class ||= begin
          klass_name = params[:resource_type]
          # Ensure all PallasTrade models are loaded so that descendants is complete
          Rails.application.eager_load! unless Rails.application.config.eager_load
          klass = PallasTrade.base_class.descendants.find { |pallastrade_klass| pallastrade_klass.name.to_s == klass_name }
          klass ||= PallasTrade.user_class if klass_name == PallasTrade.user_class.to_s
          klass ||= PallasTrade.admin_user_class if klass_name == PallasTrade.admin_user_class.to_s

          raise ActiveRecord::RecordNotFound if klass.blank?

          klass
        rescue NameError
          raise ActiveRecord::RecordNotFound
        end
      end
    end
  end
end
