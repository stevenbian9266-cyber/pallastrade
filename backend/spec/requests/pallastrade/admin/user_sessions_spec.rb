require 'rails_helper'

RSpec.describe 'Admin user sessions', type: :request do
  it 'does not redirect a successful login back to the sign-in form' do
    admin = create(:admin_user, password: 'secret', password_confirmation: 'secret')

    get '/admin_user/sign_in'
    post '/admin_user/sign_in', params: {
      admin_user: { email: admin.email, password: 'secret' }
    }

    expect(response).to redirect_to(PallasTrade.admin_path)
  end

  describe 'DELETE /admin_user/sign_out' do
    it 'redirects to the admin sign-in page instead of the storefront root' do
      admin = create(:admin_user, password: 'secret', password_confirmation: 'secret')

      get '/admin_user/sign_in'
      post '/admin_user/sign_in', params: {
        admin_user: { email: admin.email, password: 'secret' }
      }

      delete '/admin_user/sign_out', headers: { 'Accept' => 'text/html' }

      expect(response).to redirect_to('/admin_user/sign_in')
    end
  end
end
