require 'spec_helper'

RSpec.describe PallasTradeAdyen::ApplicationInfoPresenter do
  subject { described_class.new.to_h }

  let(:expected_hash) do
    {
      applicationInfo: {
        externalPlatform: {
          name: 'PallasTrade Commerce',
          version: '42.0.0',
          integrator: 'Steven Bian'
        },
        merchantApplication: {
          name: 'Community Edition',
          version: '0.0.1'
        }
      }
    }
  end

  before do
    allow(PallasTrade).to receive(:version).and_return('42.0.0')
    allow(PallasTradeAdyen).to receive(:version).and_return('0.0.1')
  end

  it 'returns the correct hash' do
    expect(subject).to eq(expected_hash)
  end
end
