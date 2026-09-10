# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch5a-definition-registry AC-007
# Rails Admin discovery must read the shared definition registry: the picker
# labels come from registry entries (so api_type renames like taxon → category
# resolve), and the form partial comes from the registry mapping.
RSpec.describe 'Admin promotion definition pickers', type: :request do
  let!(:store) { create(:store, code: 'promo_definition_admin_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PromotionRulesController).
      to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::PromotionActionsController).
      to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::PromotionsController).
      to receive(:current_store).and_return(store)
  end

  let(:promotion) { create(:promotion, store: store) }

  def create_currency_rule
    PallasTrade::Promotion::Rules::Currency.create!(promotion: promotion, preferred_currency: 'USD')
  end

  describe 'rule picker' do
    it 'labels every registered rule type from the registry' do
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_rule_path(promotion)

      expect(response).to have_http_status(:ok)
      PallasTrade::Promotions::DefinitionRegistry.rule_entries.each do |entry|
        expect(response.body).to include(entry.label)
      end
    end

    it 'renders translated labels for the renamed api_types (category / customer)' do
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_rule_path(promotion)

      expect(response.body).to include('Categories')
      expect(response.body).to include('Customers')
      expect(response.body).not_to include('translation missing')
    end

    it 'hides rule types that the promotion already has' do
      create_currency_rule
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_rule_path(promotion)

      expect(response.body).not_to include(
        PallasTrade.new_admin_promotion_rule_path(promotion, promotion_rule: { type: 'PallasTrade::Promotion::Rules::Currency' })
      )
      expect(response.body).not_to include('Currency')
    end
  end

  describe 'action picker' do
    it 'labels every registered action type from the registry' do
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_action_path(promotion)

      expect(response).to have_http_status(:ok)
      PallasTrade::Promotions::DefinitionRegistry.action_entries.each do |entry|
        expect(response.body).to include(entry.label)
      end
    end
  end

  describe 'form partial resolution' do
    it 'renders the registered form partial through the registry mapping' do
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_rule_path(
        promotion, promotion_rule: { type: 'PallasTrade::Promotion::Rules::Currency' }
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('preferred_currency')
    end

    it 'renders the action form partial through the registry mapping' do
      sign_in_as_superuser

      get PallasTrade.new_admin_promotion_action_path(
        promotion, promotion_action: { type: 'PallasTrade::Promotion::Actions::FreeShipping' }
      )

      expect(response).to have_http_status(:ok)
    end

    it 'falls back to the legacy partial name for unknown types' do
      helper = Object.new
      helper.extend(PallasTrade::Admin::PromotionRulesHelper)
      rule = instance_double(PallasTrade::PromotionRule, type: 'Whatever::Rule', key: 'whatever')

      expect(PallasTrade::Promotions::DefinitionRegistry.admin_partial_for(rule.type, kind: :rule)).to be_nil
      expect(helper.promotion_rule_form_partial(rule)).
        to eq('pallastrade/admin/promotion_rules/forms/whatever')
    end

    it 'resolves registered types through the registry mapping' do
      helper = Object.new
      helper.extend(PallasTrade::Admin::PromotionRulesHelper)
      rule = instance_double(PallasTrade::PromotionRule, type: 'PallasTrade::Promotion::Rules::Taxon', key: 'category')

      expect(helper.promotion_rule_form_partial(rule)).to eq('pallastrade/admin/promotion_rules/forms/category')
    end
  end
end
