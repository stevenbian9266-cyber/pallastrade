# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-other-新增cms博客 AC-001
RSpec.describe PallasTrade::Post, type: :model do
  let(:store) { create(:store, code: "post_spec_#{SecureRandom.hex(4)}") }

  describe 'associations' do
    it 'belongs to a store' do
      post = build(:post, store: store)
      expect(post.store).to eq(store)
    end

    it 'has one attached cover image' do
      post = build(:post, store: store)
      expect(post).to respond_to(:cover_image)
      expect(post).to respond_to(:cover_image_attachment)
    end
  end

  describe 'validations' do
    it 'requires a title' do
      expect(build(:post, store: store, title: nil)).to be_invalid
    end

    it 'auto-generates a slug from the title when blank' do
      post = create(:post, store: store, title: 'My Amazing Post', slug: nil)
      expect(post.slug).to eq('my-amazing-post')
    end

    it 'makes duplicate slugs unique with a suffix' do
      create(:post, store: store, title: 'Same Title')
      second = create(:post, store: store, title: 'Same Title')
      expect(second.slug).not_to eq('same-title')
      expect(second.slug).to start_with('same-title')
    end
  end

  describe 'scopes' do
    let!(:published_post) { create(:post, store: store, published_at: 1.day.ago) }
    let!(:draft_post) { create(:post, :draft, store: store) }
    let!(:scheduled_post) { create(:post, :scheduled, store: store) }

    it 'published returns only published posts' do
      expect(store.posts.published).to contain_exactly(published_post)
    end

    it 'drafts returns only drafts' do
      expect(store.posts.drafts).to contain_exactly(draft_post)
    end

    it 'scheduled returns only scheduled posts' do
      expect(store.posts.scheduled).to contain_exactly(scheduled_post)
    end

    it 'newest_first orders by published_at desc with drafts last' do
      create(:post, store: store, published_at: 2.days.ago)
      ordered = store.posts.newest_first.to_a
      # scheduled (future) first, then published, then draft (nil last)
      expect(ordered.first).to eq(scheduled_post)
      expect(ordered.second).to eq(published_post)
      expect(ordered.last).to eq(draft_post)
    end
  end

  describe '#published?' do
    it 'is false for a draft' do
      expect(build(:post, :draft).published?).to be(false)
    end

    it 'is false for a scheduled post' do
      expect(build(:post, :scheduled).published?).to be(false)
    end

    it 'is true for a published post' do
      expect(build(:post).published?).to be(true)
    end
  end

  describe '#scheduled?' do
    it 'is true for a scheduled post' do
      expect(build(:post, :scheduled).scheduled?).to be(true)
    end

    it 'is false for a draft' do
      expect(build(:post, :draft).scheduled?).to be(false)
    end
  end

  describe 'translations' do
    it 'stores per-locale title and excerpt' do
      post = create(:post, store: store, title: 'English title')
      I18n.with_locale(:fr) do
        post.update!(title: 'Titre français', excerpt: 'Extrait français')
      end

      expect(post.title).to eq('English title')
      I18n.with_locale(:fr) do
        expect(post.reload.title).to eq('Titre français')
        expect(post.excerpt).to eq('Extrait français')
      end
    end

    it 'stores rich text body per locale' do
      post = create(:post, store: store, body: '<p>Hello</p>')
      expect(post.body.to_plain_text).to eq('Hello')
    end
  end
end
