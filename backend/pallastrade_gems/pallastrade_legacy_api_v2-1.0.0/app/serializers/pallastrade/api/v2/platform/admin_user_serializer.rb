# frozen_string_literal: true

module PallasTrade
  module Api
    module V2
      module Platform
        class AdminUserSerializer < BaseSerializer
          set_type :admin_user

          attributes :email, :first_name, :last_name, :created_at, :updated_at
        end
      end
    end
  end
end
