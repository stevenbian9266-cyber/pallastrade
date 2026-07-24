require 'rails_helper'

RSpec.describe 'PallasTrade content locales' do
  it 'registers every supported content locale with I18n and Mobility' do
    registered = I18n.available_locales.map(&:to_s)

    expect(PallasTrade::Locales::ALL - registered).to be_empty
    expect { Mobility.with_locale(:pt) { nil } }.not_to raise_error
  end
end
