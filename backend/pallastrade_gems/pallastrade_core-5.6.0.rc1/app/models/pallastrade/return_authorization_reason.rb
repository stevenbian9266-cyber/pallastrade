module PallasTrade
  class ReturnAuthorizationReason < PallasTrade.base_class
    has_prefix_id :rar

    include PallasTrade::NamedType

    has_many :return_authorizations, dependent: :restrict_with_error
  end
end
