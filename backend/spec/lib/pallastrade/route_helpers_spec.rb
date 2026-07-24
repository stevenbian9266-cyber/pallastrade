require 'rails_helper'
require 'uri'

RSpec.describe PallasTrade do
  it 'generates engine URLs with a canonical host outside a request' do
    url = URI.parse(described_class.admin_products_url)

    expect(url.host).to be_present
    expect(url.path).to eq('/admin/products')
  end
end
