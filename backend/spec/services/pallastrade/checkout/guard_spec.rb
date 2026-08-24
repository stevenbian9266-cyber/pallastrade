require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-001/002/003/004 — 下单前置校验（登录/黑名单/风控）
RSpec.describe PallasTrade::Checkout::Guard, type: :service do
  let(:store) { PallasTrade::Store.default }
  let(:user) { create(:user) }

  describe '#call' do
    it 'AC-001: 未登录用户返回 login_required 拦截' do
      result = described_class.call(user: nil)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:login_required)
      expect(result.error.value[:message]).to be_present
    end

    it 'AC-002: 黑名单用户返回 user_blacklisted 拦截' do
      user.update_column(:blacklisted_at, Time.current)
      expect(user).to be_blacklisted

      result = described_class.call(user: user)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:user_blacklisted)
      expect(result.error.value[:message]).to be_present
    end

    it 'AC-003: 风控钩子返回拦截 → 透传 code/message' do
      PallasTrade::Config[:risk_assessment] = lambda { |user:, order_params:|
        { code: :fraud_suspected, message: 'manual review' }
      }
      result = described_class.call(user: user)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:fraud_suspected)
      expect(result.error.value[:message]).to eq('manual review')
    ensure
      PallasTrade::Config[:risk_assessment] = nil
    end

    it 'AC-004: 正常用户通过校验（返回 success + user）' do
      result = described_class.call(user: user)
      expect(result).to be_success
      expect(result.value).to eq(user)
    end
  end
end
