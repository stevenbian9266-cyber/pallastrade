# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-promotions-promo-batch6-pr-p9-cleanup AC-003 AC-004 AC-005
#
# Promotions → Categories 最小后台（batch5b 审计 D2）：PromotionCategory 原本只有
# Admin API，没有后台入口。覆盖 CRUD、权限闸门、以及促销表单里的分类选择器。
RSpec.describe 'Admin promotion categories', type: :request do
  let!(:store) { create(:store, code: 'promo_categories_store', default: true) }
  let(:admin) do
    create(:admin_user, email: 'promo_cat_admin@example.com', password: 'secret',
                        password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PromotionCategoriesController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::PromotionsController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/promotion_categories' do
    it 'lists categories' do
      PallasTrade::PromotionCategory.create!(name: 'Seasonal', code: 'SEASON')

      get '/admin/promotion_categories'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Seasonal')
      expect(response.body).to include(PallasTrade.t('admin.promotion_categories.title'))
    end

    it 'renders the new page with the form fields' do
      get '/admin/promotion_categories/new'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.promotion_categories.new_promotion_category'))
      expect(response.body).to include('promotion_category[name]')
    end
  end

  describe 'POST /admin/promotion_categories' do
    it 'creates a category' do
      post '/admin/promotion_categories', params: { promotion_category: { name: 'Flash Sale', code: 'FLASH' } }

      expect(response).to have_http_status(:see_other)
      expect(PallasTrade::PromotionCategory.find_by(code: 'FLASH')).to be_present
    end

    it 'rejects a category without a name' do
      post '/admin/promotion_categories', params: { promotion_category: { name: '' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(PallasTrade::PromotionCategory.count).to eq(0)
    end
  end

  describe 'PATCH /admin/promotion_categories/:id' do
    it 'updates a category' do
      category = PallasTrade::PromotionCategory.create!(name: 'Old Name', code: 'OLD')

      patch "/admin/promotion_categories/#{category.prefixed_id}", params: { promotion_category: { name: 'New Name' } }

      expect(response).to have_http_status(:see_other)
      expect(category.reload.name).to eq('New Name')
    end
  end

  describe 'DELETE /admin/promotion_categories/:id' do
    it 'destroys a category' do
      category = PallasTrade::PromotionCategory.create!(name: 'Doomed', code: 'DOOM')

      delete "/admin/promotion_categories/#{category.prefixed_id}"

      expect(response).to have_http_status(:see_other)
      expect(PallasTrade::PromotionCategory.find_by(id: category.id)).to be_nil
    end
  end

  describe 'promotion form category selector（D2=A 最小 UI）' do
    let(:category) { PallasTrade::PromotionCategory.create!(name: 'Loyalty', code: 'LOYAL') }
    let(:promotion) { create(:promotion, store: store, name: 'Form Check', kind: :automatic, code: 'FORMCAT1') }

    it 'renders the category select on the promotion edit page' do
      category

      get PallasTrade.edit_admin_promotion_path(promotion)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('promotion[promotion_category_id]')
      expect(response.body).to include('Loyalty')
    end

    it 'persists the selected category' do
      patch PallasTrade.admin_promotion_path(promotion),
            params: { promotion: { promotion_category_id: category.id } }

      expect(response).to have_http_status(:see_other)
      expect(promotion.reload.promotion_category_id).to eq(category.id)
    end
  end

  describe 'permission gate（capability 单源）' do
    def grant_role(**permissions)
      role = create(:role, name: "promo_cat_#{SecureRandom.hex(3)}")
      permissions.each do |resource, actions|
        actions.each do |action|
          role.role_permissions.create!(permission_type: 'function', resource: resource.to_s,
                                        action: action.to_s, allowed: true)
        end
      end
      create(:role_user, user: admin, role: role, resource: store, store: store)
    end

    it 'denies access without the promotion_categories capability' do
      PallasTrade::RoleUser.where(user: admin).delete_all

      grant_role(promotions: %w[read create update destroy])

      get '/admin/promotion_categories'

      expect(response).not_to have_http_status(:ok)
    end

    it 'allows access once promotion_categories is granted' do
      PallasTrade::RoleUser.where(user: admin).delete_all

      grant_role(promotions: %w[read create update destroy], promotion_categories: %w[read create update destroy])

      get '/admin/promotion_categories'

      expect(response).to have_http_status(:ok)
    end
  end
end
