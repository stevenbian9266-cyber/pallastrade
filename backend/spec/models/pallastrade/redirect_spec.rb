# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PallasTrade::Redirect, type: :model do
  let(:store) { @default_store }

  describe 'validations' do
    it 'is valid with valid attributes' do
      redirect = build(:redirect, store: store)
      expect(redirect).to be_valid
    end

    it 'requires from_path and to_path' do
      redirect = build(:redirect, store: store, from_path: nil, to_path: nil)
      expect(redirect).not_to be_valid
      expect(redirect.errors[:from_path]).to include("can't be blank")
      expect(redirect.errors[:to_path]).to include("can't be blank")
    end

    it 'enforces unique from_path per store' do
      create(:redirect, store: store, from_path: '/old')
      duplicate = build(:redirect, store: store, from_path: '/old')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:from_path]).to include('has already been taken')
    end

    it 'allows the same from_path on different stores' do
      other = create(:store, code: 'redirects_other_store', default: false)
      create(:redirect, store: store, from_path: '/old')
      expect(build(:redirect, store: other, from_path: '/old')).to be_valid
    end

    it 'rejects external to_path URLs' do
      redirect = build(:redirect, store: store, to_path: 'https://evil.example.com/x')
      expect(redirect).not_to be_valid
      expect(redirect.errors[:to_path]).to include('must be an internal path (no external URLs)')
    end
  end

  describe 'normalization' do
    it 'strips a leading origin from from_path' do
      redirect = build(:redirect, store: store, from_path: 'https://shop.example.com/old-product')
      expect(redirect).to be_valid
      expect(redirect.from_path).to eq('/old-product')
    end

    it 'adds a leading slash and strips trailing slash' do
      redirect = build(:redirect, store: store, from_path: 'old-product/', to_path: 'new-product/')
      redirect.valid?
      expect(redirect.from_path).to eq('/old-product')
      expect(redirect.to_path).to eq('/new-product')
    end

    it 'keeps root slash as-is' do
      redirect = build(:redirect, store: store, from_path: '/', to_path: '/home')
      redirect.valid?
      expect(redirect.from_path).to eq('/')
    end
  end

  describe '.normalize_path' do
    it 'normalizes common variants' do
      expect(described_class.normalize_path('https://shop.example.com/a/b/')).to eq('/a/b')
      expect(described_class.normalize_path('a/b')).to eq('/a/b')
      expect(described_class.normalize_path('/a/b')).to eq('/a/b')
      expect(described_class.normalize_path('/')).to eq('/')
    end
  end
end
