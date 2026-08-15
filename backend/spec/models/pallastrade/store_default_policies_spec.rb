# frozen_string_literal: true

require 'rails_helper'

# PRD-20260815-catalog-邮件管理整合 / bugfix：默认 policy 名称翻译 key 大小写
# 回归：create_default_policies 用小写 pallastrade.* key（此前大写 PallasTrade.*
# 导致 name/slug 写入 "Translation missing: ..."）。
RSpec.describe 'Store default policies i18n', type: :model do
  let(:store) { create(:store, code: 'store_policies_i18n') }

  it 'creates default policies with translated names (no "Translation missing")' do
    names = store.policies.map(&:name)

    expect(names).to include('Terms of Service')
    expect(names).to include('Privacy Policy')
    expect(names).to include('Returns Policy')
    expect(names).to include('Shipping Policy')
    expect(names.join(' ')).not_to include('Translation missing')
  end

  it 'creates default policies with clean slugs' do
    slugs = store.policies.map(&:slug)

    expect(slugs).to include('terms-of-service')
    expect(slugs).to include('privacy-policy')
    expect(slugs).not_to include(/translation-missing/)
  end
end
