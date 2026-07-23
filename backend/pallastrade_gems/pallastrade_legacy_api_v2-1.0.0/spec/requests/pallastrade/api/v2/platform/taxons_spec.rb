require 'spec_helper'

describe 'Platform API v2 Taxons API' do
  include_context 'Platform API v2'

  let(:store) { @default_store }
  let(:taxonomy) { create(:taxonomy, store: store, name: PallasTrade.t(:taxonomy_categories_name)) }
  let(:store_2) { create(:store) }
  let(:bearer_token) { { 'Authorization' => valid_authorization } }

  describe 'taxons#index' do
    let!(:taxon) { create(:taxon, name: 'T-Shirts', taxonomy: taxonomy) }
    let!(:taxon_2) { create(:taxon, name: 'Pants', taxonomy: taxonomy) }
    let!(:taxon_3) { create(:taxon, name: 'T-Shirts', taxonomy: create(:taxonomy, store: store_2)) }

    context 'filtering' do
      before { get '/api/v2/platform/taxons?filter[name_i_cont]=shirt', headers: bearer_token }

      it 'returns taxons with matching name' do
        expect(json_response['data'].count).to eq 1
        expect(json_response['data'].first).to have_id(taxon.id.to_s)
        expect(json_response['data'].first).to have_relationships(:taxonomy, :parent, :children)
      end
    end

    xcontext 'sorting' do
      before { get '/api/v2/platform/taxons?sort=name', headers: bearer_token }

      it 'returns taxons sorted by name' do
        expect(json_response['data'].count).to eq 4
        expect(json_response['data'].second).to have_id(taxon_2.id.to_s)
      end
    end
  end

  describe 'taxons#show' do
    let!(:taxon) { create(:taxon, name: 'T-Shirts', taxonomy: taxonomy) }

    context 'with valid id' do
      before { get "/api/v2/platform/taxons/#{taxon.id}", headers: bearer_token }

      it 'returns taxon' do
        expect(json_response['data']).to have_id(taxon.id.to_s)
        expect(json_response['data']).to have_relationships(:taxonomy, :parent, :children, :products)
      end
    end
  end

  shared_examples 'a resource containing metadata' do
    describe 'public metadata' do
      let(:metadata_params) { { public_metadata: public_metadata_params } }

      describe 'string entry' do
        let(:public_metadata_params) { { ability_to_recycle: '60%' } }

        it 'adds the metadata property' do
          expect(json_response['data']['attributes']['public_metadata']['ability_to_recycle']).to eq('60%')
        end
      end

      describe 'number entry' do
        let(:public_metadata_params) { { profitability: 3.4 } }

        it { expect(json_response['data']['attributes']['public_metadata']['profitability']).to eq('3.4') }
      end

      describe 'boolean entry' do
        let(:public_metadata_params) { { in_foreign_country: true } }

        it { expect(json_response['data']['attributes']['public_metadata']['in_foreign_country']).to eq('true') }
      end

      describe 'array entry' do
        let(:public_metadata_params) { { top_years: %w[2011 2016 2020] } }

        it { expect(json_response['data']['attributes']['public_metadata']['top_years']).to eq(%w[2011 2016 2020]) }
      end
    end

    describe 'private metadata' do
      let(:metadata_params) { { private_metadata: private_metadata_params } }

      describe 'string entry' do
        let(:private_metadata_params) { { ability_to_recycle: '60%' } }

        it { expect(json_response['data']['attributes']['private_metadata']['ability_to_recycle']).to eq('60%') }
      end

      describe 'number entry' do
        let(:private_metadata_params) { { profitability: 3.4 } }

        it { expect(json_response['data']['attributes']['private_metadata']['profitability']).to eq('3.4') }
      end

      describe 'boolean entry' do
        let(:private_metadata_params) { { in_foreign_country: false } }

        it { expect(json_response['data']['attributes']['private_metadata']['in_foreign_country']).to eq('false') }
      end

      describe 'array entry' do
        let(:private_metadata_params) { { top_years: %w[2011 2016 2020] } }

        it { expect(json_response['data']['attributes']['private_metadata']['top_years']).to eq(%w[2011 2016 2020]) }
      end
    end
  end

  describe 'taxons#update for metadata' do
    let!(:taxon) { create(:taxon, name: 'T-Shirts', taxonomy: taxonomy) }

    before do
      patch "/api/v2/platform/taxons/#{taxon.id}",
            headers: bearer_token,
            params: { taxon: metadata_params }
    end

    it_behaves_like 'a resource containing metadata'
  end

  describe 'taxons#create for metadata' do
    before do
      post '/api/v2/platform/taxons/',
           headers: bearer_token,
           params: {
             taxon: {
               name: 'Tires',
               taxonomy_id: taxonomy.id,
               parent_id: taxonomy.root.id
             }.merge(metadata_params)
           }
    end

    it_behaves_like 'a resource containing metadata'
  end

  describe 'taxons#reposition' do
    let!(:taxon_a) { create(:taxon, name: 'T-Shirts', taxonomy: taxonomy) }
    let!(:taxon_b) { create(:taxon, name: 'Shorts', taxonomy: taxonomy) }
    let!(:taxon_c) { create(:taxon, name: 'Pants', taxonomy: taxonomy) }

    context 'with no params' do
      let(:params) do
        {
          taxon: {
            new_parent_id: nil,
            new_position_idx: nil
          }
        }
      end

      before do
        patch "/api/v2/platform/taxons/#{taxon_a.id}/reposition", headers: bearer_token, params: params
      end

      it_behaves_like 'returns 404 HTTP status'
    end

    context 'with none existing parent ID' do
      let(:params) do
        {
          taxon: {
            new_parent_id: 999129192192,
            new_position_idx: 0
          }
        }
      end

      before do
        patch "/api/v2/platform/taxons/#{taxon_a.id}/reposition", headers: bearer_token, params: params
      end

      it_behaves_like 'returns 404 HTTP status'
    end

    context 'with correct params' do
      let(:params) do
        {
          taxon: {
            new_parent_id: taxon_c.id,
            new_position_idx: 0
          }
        }
      end

      before do
        patch "/api/v2/platform/taxons/#{taxon_a.id}/reposition", headers: bearer_token, params: params
      end

      it_behaves_like 'returns 200 HTTP status'

      it 'taxon_a can be nested inside another taxon_c' do
        reload_taxons

        expect(taxon_a.permalink).to eq("#{taxonomy.root.permalink}/pants/t-shirts")
        expect(taxon_a.parent_id).to eq(taxon_c.id)
        expect(taxon_a.depth).to eq(2)
      end
    end

    context 'with correct params moving within the same taxon' do
      let(:params) do
        {
          taxon: {
            new_parent_id: taxon_b.id,
            new_position_idx: 0
          }
        }
      end

      before do
        patch "/api/v2/platform/taxons/#{taxon_a.id}/reposition", headers: bearer_token, params: params
      end

      it_behaves_like 'returns 200 HTTP status'

      it 're-indexes the taxon' do
        reload_taxons

        expect(taxon_a.parent_id).to eq(taxon_b.id)
        expect(taxon_a.lft).to eq(taxon_b.lft + 1)
      end
    end

    def reload_taxons
      taxon_a.reload
      taxon_b.reload
      taxon_c.reload
    end
  end
end
