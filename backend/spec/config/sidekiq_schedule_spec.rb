# frozen_string_literal: true

# bugfix C6 (FIN-P4 review 批1, 2026-09-06): 注册 financial reconcile sweeper 到
# PALLAS_CART_SCHEDULE —— 此前自动 reconcile/journal-missing 补记闭环只在手动 rake，
# 部署中从不运行。schedule 由 config/initializers/pallastrade_sidekiq_cron.rb 加载。
require 'rails_helper'

RSpec.describe 'sidekiq schedule (config/sidekiq_schedule.rb)' do
  it 'registers the financial reconcile sweeper (bugfix C6)' do
    load Rails.root.join('config/sidekiq_schedule.rb') unless defined?(PALLAS_CART_SCHEDULE)

    entry = PALLAS_CART_SCHEDULE.find { |e| e[:name] == 'financial_reconcile_sweeper' }
    expect(entry).to be_present
    expect(entry[:class]).to eq('PallasTrade::Reconciliations::ReconcileSweeperJob')
    expect(entry[:cron]).to be_present
    expect(entry[:queue]).to eq('default')
  end

  # PRD-20260910-promotions-promo-batch3b-redemption-hardening AC-004
  # reserved 行 TTL 出口必须被周期调度，否则悬挂占用永不释放。
  it 'registers the promotion redemption expiry sweeper (batch3b AC-004)' do
    load Rails.root.join('config/sidekiq_schedule.rb') unless defined?(PALLAS_CART_SCHEDULE)

    entry = PALLAS_CART_SCHEDULE.find { |e| e[:name] == 'promotion_redemption_expiry' }
    expect(entry).to be_present
    expect(entry[:class]).to eq('PallasTrade::Promotions::Redemption::ExpireSweeperJob')
    expect(entry[:cron]).to eq('*/5 * * * *')
    expect(entry[:queue]).to eq('default')
  end
end
