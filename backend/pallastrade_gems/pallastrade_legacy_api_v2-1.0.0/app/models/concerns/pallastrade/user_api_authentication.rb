module PallasTrade
  module UserApiAuthentication
    def generate_pallastrade_api_key!
      self.pallastrade_api_key = generate_pallastrade_api_key
      save!
    end

    def clear_pallastrade_api_key!
      self.pallastrade_api_key = nil
      save!
    end

    private

    def generate_pallastrade_api_key
      SecureRandom.hex(24)
    end
  end
end
