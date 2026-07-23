module PallasTrade
  module Seeds
    class ReturnsEnvironment
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::RefundReason.find_or_create_by!(name: 'Return processing', mutable: false)
        [
          'Better price available',
          'Missed estimated delivery date',
          'Missing parts or accessories',
          'Damaged/Defective',
          'Different from what was ordered',
          'Different from description',
          'No longer needed/wanted',
          'Accidental order',
          'Unauthorized purchase',
        ].each do |name|
          PallasTrade::ReturnAuthorizationReason.find_or_create_by!(name: name)
        end
        PallasTrade::ReimbursementType.find_or_create_by!(name: 'Store Credit', type: 'PallasTrade::ReimbursementType::StoreCredit')
        PallasTrade::ReimbursementType.find_or_create_by!(name: 'Exchange', type: 'PallasTrade::ReimbursementType::Exchange')
        PallasTrade::ReimbursementType.find_or_create_by!(name: 'Original payment', type: 'PallasTrade::ReimbursementType::OriginalPayment')
      end
    end
  end
end
