module SpreeStripe
  class UpdateCustomerJob < BaseJob
    def perform(user_id)
      return unless PallasTrade.user_class.present?

      user = PallasTrade.user_class.find(user_id)
      SpreeStripe::UpdateCustomer.new.call(user: user)
    end
  end
end
