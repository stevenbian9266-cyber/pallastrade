# == Schema Information
#
# Table name: pallastrade_reports
#
#  id          :bigint           not null, primary key
#  type        :string
#  currency    :string
#  date_from   :datetime
#  date_to     :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  store_id    :bigint           not null
#  user_id     :bigint
#
FactoryBot.define do
  factory :report, class: 'PallasTrade::Reports::SalesTotal' do
    association :store, factory: :store
    association :user, factory: :admin_user
    type { 'PallasTrade::Reports::SalesTotal' }
    currency { 'USD' }
    date_from { 1.month.ago }
    date_to { Time.current }
  end

  factory :products_performance_report, class: 'PallasTrade::Reports::ProductsPerformance' do
    association :store, factory: :store
    association :user, factory: :admin_user
    type { 'PallasTrade::Reports::ProductsPerformance' }
    currency { 'USD' }
    date_from { 1.month.ago }
    date_to { Time.current }
  end
end
