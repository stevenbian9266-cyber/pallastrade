# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-bulk-media
#   AC-001 预览零写入           AC-002 预览/执行口径一致
#   AC-003 商品级+变体级均清空   AC-004 primary_media 指针清空
#   AC-005 不留悬空 VariantMedia AC-006 计数守恒
#   AC-007 权限不足零写入        AC-010 业务数据不动
#   AC-011 未选中不受影响        AC-012 全无媒体的整批
RSpec.describe PallasTrade::Products::BulkMediaRemoval, type: :service do
  let(:store) { create(:store, code: "bmr_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD') }
  let(:ability) { instance_double(PallasTrade::Ability, can?: true) }
  let(:denied_ability) { instance_double(PallasTrade::Ability, can?: false) }

  def build_service(products, ability: self.ability)
    described_class.new(products: products, ability: ability)
  end

  def product_with_media
    product = create(:product, store: store)
    create(:asset, viewable: product)
    product.reload
  end

  describe 'AC-003 removing media' do
    it 'clears the product gallery and every variant image' do
      product = product_with_media
      variant = create(:variant, product: product)
      create(:asset, viewable: variant)

      expect(product.media.count).to eq(1)
      expect(variant.images.count).to eq(1)

      result = build_service([product]).call

      expect(result.updated_count).to eq(1)
      expect(product.reload.media).to be_empty
      expect(variant.reload.images).to be_empty
      expect(PallasTrade::Asset.where(viewable_type: 'PallasTrade::Product', viewable_id: product.id)).to be_empty
      expect(PallasTrade::Asset.where(viewable_type: 'PallasTrade::Variant', viewable_id: variant.id)).to be_empty
    end

    it 'treats a product whose only media is variant-level as having media' do
      product = create(:product, store: store)
      variant = product.master
      create(:asset, viewable: variant)

      expect(product.reload.media).to be_empty
      expect(build_service([product]).call.updated_count).to eq(1)
      expect(variant.reload.images).to be_empty
    end
  end

  describe 'AC-001 preview is zero-write' do
    it 'changes neither assets nor pointers' do
      product = product_with_media
      variant = create(:variant, product: product)
      variant_asset = create(:asset, viewable: variant)
      product.update!(primary_media: product.media.first)
      variant.update!(primary_media: variant_asset)

      assets_before = PallasTrade::Asset.count
      product_primary_before = product.reload.primary_media_id
      variant_primary_before = variant.reload.primary_media_id

      preview = build_service([product]).preview

      expect(preview.updated_count).to eq(1)
      expect(PallasTrade::Asset.count).to eq(assets_before)
      expect(product.reload.primary_media_id).to eq(product_primary_before)
      expect(variant.reload.primary_media_id).to eq(variant_primary_before)
      expect(product.reload.media).not_to be_empty
    end
  end

  describe 'AC-004 primary_media pointer' do
    it 'nulls primary_media_id on both the product and its variants' do
      product = product_with_media
      variant = create(:variant, product: product)
      variant_asset = create(:asset, viewable: variant)
      product.update!(primary_media: product.media.first)
      variant.update!(primary_media: variant_asset)

      build_service([product]).call

      expect(product.reload.primary_media_id).to be_nil
      expect(variant.reload.primary_media_id).to be_nil
    end
  end

  describe 'AC-005 variant/media links' do
    it 'leaves no VariantMedia row pointing at a deleted asset' do
      product = product_with_media
      variant = create(:variant, product: product)
      asset = product.media.first
      PallasTrade::VariantMedia.create!(variant: variant, asset: asset)

      build_service([product]).call

      expect(PallasTrade::VariantMedia.where(media_id: asset.id)).to be_empty
    end
  end

  describe 'AC-002 preview matches execution' do
    it 'reports the same counts whichever path runs' do
      with_media = product_with_media
      without = create(:product, store: store)
      also_with = product_with_media
      products = [with_media, without, also_with]

      preview = build_service(products).preview
      result = build_service(products).call

      expect(preview.selected_count).to eq(result.selected_count)
      expect(preview.updated_count).to eq(result.updated_count)
      expect(preview.skipped_count).to eq(result.skipped_count)
    end
  end

  describe 'AC-006 count conservation' do
    it 'keeps updated + skipped equal to the selection' do
      with_media = product_with_media
      without = create(:product, store: store)

      result = build_service([with_media, without]).call

      expect(result.selected_count).to eq(2)
      expect(result.updated_count).to eq(1)
      expect(result.skipped_count).to eq(1)
      expect(result.updated_count + result.skipped_count).to eq(result.selected_count)
    end
  end

  describe 'AC-012 a batch with no media at all' do
    it 'reports 0 updated and N skipped instead of failing' do
      products = [create(:product, store: store), create(:product, store: store)]

      result = build_service(products).call

      expect(result.updated_count).to eq(0)
      expect(result.skipped_count).to eq(2)
      expect(result.warnings).to be_empty
    end
  end

  describe 'AC-007 without asset permission' do
    it 'changes nothing and reports the reason' do
      product = product_with_media
      assets_before = PallasTrade::Asset.count

      result = build_service([product], ability: denied_ability).call

      expect(result.updated_count).to eq(0)
      expect(result.skipped_count).to eq(1)
      expect(result.warnings[:media_permission_denied]).to eq(1)
      expect(PallasTrade::Asset.count).to eq(assets_before)
      expect(product.reload.media).not_to be_empty
    end
  end

  describe 'AC-010 business data is untouched' do
    it 'leaves the product attributes alone' do
      product = product_with_media
      product.update!(status: 'active')
      before = product.reload.attributes.slice('status', 'slug', 'name', 'sku')

      build_service([product]).call

      expect(product.reload.attributes.slice('status', 'slug', 'name', 'sku')).to eq(before)
    end
  end

  describe 'AC-011 unselected products' do
    it 'leaves other products of the same store alone' do
      selected = product_with_media
      other = product_with_media

      build_service([selected]).call

      expect(selected.reload.media).to be_empty
      expect(other.reload.media).not_to be_empty
    end
  end
end
