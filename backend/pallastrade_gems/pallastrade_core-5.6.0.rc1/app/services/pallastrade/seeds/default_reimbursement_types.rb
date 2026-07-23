module PallasTrade
  module Seeds
    class DefaultReimbursementTypes
      prepend PallasTrade::ServiceModule::Base

      def call
        # FIXME: we should use translations here
        PallasTrade::RefundReason.find_or_create_by!(name: 'Return processing', mutable: false)
      end
    end
  end
end
