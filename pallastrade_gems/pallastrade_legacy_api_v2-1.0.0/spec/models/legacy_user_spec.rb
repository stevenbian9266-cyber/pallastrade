require 'spec_helper'

module PallasTrade
  describe LegacyUser, type: :model do
    let(:user) { LegacyUser.new }

    it 'can generate an API key' do
      expect(user).to receive(:save!)
      user.generate_pallastrade_api_key!
      expect(user.pallastrade_api_key).not_to be_blank
    end

    it 'can clear an API key' do
      expect(user).to receive(:save!)
      user.clear_pallastrade_api_key!
      expect(user.pallastrade_api_key).to be_blank
    end
  end
end
