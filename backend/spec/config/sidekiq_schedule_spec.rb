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
end
