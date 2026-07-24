module PallasTrade
  module Seeds
    class PaymentMethods
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::Store.all.find_each do |store|
          payment_method = store.payment_methods.find_or_initialize_by(
            type: 'PallasTrade::PaymentMethod::StoreCredit'
          )
          next if payment_method.persisted?

          payment_method.name = PallasTrade.t(:store_credit_name)
          payment_method.description = PallasTrade.t(:store_credit_name)
          payment_method.active = true
          payment_method.save!
        end
      end
    end
  end
end
