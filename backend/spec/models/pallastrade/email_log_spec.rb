# frozen_string_literal: true

require 'rails_helper'

# PRD-20260815-catalog-邮件管理整合 AC-005
RSpec.describe PallasTrade::EmailLog, type: :model do
  let(:store) { create(:store, code: 'emlg_model_test') }

  describe 'validations' do
    it 'is valid with a store, mailer, action and recipient' do
      expect(build(:email_log, store: store)).to be_valid
    end

    it 'rejects a missing recipient' do
      expect(build(:email_log, store: store, to: nil)).to be_invalid
    end
  end

  describe 'scopes' do
    it 'orders recent by sent_at desc' do
      old = create(:email_log, store: store, sent_at: 2.days.ago)
      new = create(:email_log, store: store, sent_at: 1.day.ago)
      expect(store.email_logs.recent.first).to eq(new)
      expect(store.email_logs.recent.last).to eq(old)
    end

    it 'filters by status' do
      create(:email_log, store: store, status: 'sent')
      failed = create(:email_log, store: store, status: 'failed')
      expect(store.email_logs.by_status('failed')).to eq([failed])
    end
  end

  describe '#failed?' do
    it 'returns true for failed status' do
      expect(build(:email_log, store: store, status: 'failed')).to be_failed
      expect(build(:email_log, store: store, status: 'sent')).not_to be_failed
    end
  end
end
