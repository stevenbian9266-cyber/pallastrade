# frozen_string_literal: true

require 'spec_helper'

# PRD-20260910-promotions-promo-batch5a-definition-registry AC-002 AC-007
# Admin API discovery (`/promotion_rules/types`, `/promotion_actions/types`,
# `/promotion_actions/calculators`) and the Admin API type allowlist must both
# read the shared definition registry.
RSpec.describe '/api/v3/admin promotion definition discovery', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:registry) { PallasTrade::Promotions::DefinitionRegistry }

  describe 'GET /api/v3/admin/promotion_rules/types (AC-007)' do
    it 'enumerates exactly the registry keys' do
      get '/api/v3/admin/promotion_rules/types', headers: headers

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['data']

      expect(rows.map { |row| row['type'] }).to match_array(registry.keys(:rule))
      expect(rows.map { |row| row['label'] }).to include('Categories', 'Customers')
      expect(rows.find { |row| row['type'] == 'category' }['preference_schema']).to be_a(Array)
    end

    it 'stays in sync with the registry after a runtime registration' do
      extra = Class.new(PallasTrade::PromotionRule) do
        def self.api_type
          'spec_discovery_rule'
        end

        def self.human_name
          'Spec Discovery Rule'
        end
      end
      PallasTrade.promotions.rules << extra

      begin
        get '/api/v3/admin/promotion_rules/types', headers: headers

        expect(response.parsed_body['data'].map { |row| row['type'] }).to include('spec_discovery_rule')
      ensure
        PallasTrade.promotions.rules.delete(extra)
      end
    end
  end

  describe 'GET /api/v3/admin/promotion_actions/types (AC-007)' do
    it 'enumerates exactly the registry keys' do
      get '/api/v3/admin/promotion_actions/types', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].map { |row| row['type'] }).to match_array(registry.keys(:action))
    end
  end

  describe 'GET /api/v3/admin/promotion_actions/calculators (AC-002)' do
    it 'matches the calculator bucket exposed by the registry' do
      get '/api/v3/admin/promotion_actions/calculators',
          params: { type: 'PallasTrade::Promotion::Actions::CreateAdjustment' },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].map { |row| row['type'] }).
        to match_array(registry.calculators_for('create_adjustment').map(&:to_s))
    end
  end

  describe 'type allowlist for writes (AC-007)' do
    it 'accepts every registered rule type and rejects an unregistered one' do
      promotion = create(:promotion, store: store)

      post "/api/v3/admin/promotions/#{promotion.prefixed_id}/promotion_rules",
           params: { type: 'currency', preferences: { currency: 'USD' } },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['type']).to eq('currency')
      expect(response.parsed_body['preferences']).to eq('currency' => 'USD')

      post "/api/v3/admin/promotions/#{promotion.prefixed_id}/promotion_rules",
           params: { type: 'not_registered' },
           headers: headers

      expect(response).to have_http_status(422)
    end
  end
end
