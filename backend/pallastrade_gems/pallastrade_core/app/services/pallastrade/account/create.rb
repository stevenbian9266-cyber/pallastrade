module PallasTrade
  module Account
    class Create
      prepend PallasTrade::ServiceModule::Base

      def call(user_params: {})
        user = PallasTrade.user_class.new(user_params)

        if user.save
          success(user)
        else
          failure(user)
        end
      end
    end
  end
end
