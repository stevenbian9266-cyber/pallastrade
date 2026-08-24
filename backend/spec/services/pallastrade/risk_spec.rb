require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-003/053 — 风控评估（可配置钩子 + 默认频率限制）
RSpec.describe PallasTrade::Risk::Assessment, type: :service do
  let(:store) { PallasTrade::Store.default }
  let(:user) { create(:user) }

  describe '#call' do
    it 'AC-003: 未登录返回 login_required' do
      result = described_class.call(user: nil)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:login_required)
    end

    it 'AC-053: 默认规则——下单频率超过阈值时拦截' do
      PallasTrade::Config[:order_frequency_limit_per_minute] = 1
      # 已有一笔近期订单（基础 order factory，避免 line_item/inventory 依赖）
      create(:order, store: store, user: user, completed_at: Time.current, status: 'placed')

      result = described_class.call(user: user)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:too_many_orders)
    ensure
      PallasTrade::Config[:order_frequency_limit_per_minute] = nil
    end

    it 'AC-053: 默认规则——频率未超阈值时通过' do
      PallasTrade::Config[:order_frequency_limit_per_minute] = 5
      result = described_class.call(user: user)
      expect(result).to be_success
    ensure
      PallasTrade::Config[:order_frequency_limit_per_minute] = nil
    end

    it 'AC-003: 可注入自定义评估钩子（规则返回 nil 通过 / 返回 hash 拦截）' do
      PallasTrade::Config[:risk_assessment] = lambda { |user:, order_params:|
        order_params[:amount].to_i > 1000 ? { code: :high_amount, message: 'amount too high' } : nil
      }

      expect(described_class.call(user: user, order_params: { amount: 2000 })).to be_failure
      result = described_class.call(user: user, order_params: { amount: 100 })
      expect(result).to be_success
    ensure
      PallasTrade::Config[:risk_assessment] = nil
    end
  end
end
