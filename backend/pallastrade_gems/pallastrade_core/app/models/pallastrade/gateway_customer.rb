module PallasTrade
  class GatewayCustomer < PallasTrade.base_class
    has_prefix_id :gcus

    belongs_to :payment_method, class_name: 'PallasTrade::PaymentMethod'
    belongs_to :user, class_name: PallasTrade.user_class.to_s

    validates :payment_method, presence: true
    validates :user, presence: true
    validates :profile_id, presence: true
    validates :payment_method_id, uniqueness: { scope: :user_id }

    encrypts :profile_id, deterministic: true if Rails.configuration.active_record.encryption.include?(:primary_key)
  end
end
