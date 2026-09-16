# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f1-reviews —— 评论图片（预签上传 + 归属校验 + 上限）
#
#   AC-001 ← FR-001：≤3 张、jpg/png/webp、≤5MB（模型校验）
#   AC-004 ← FR-004：POST /api/v3/store/direct_uploads 预签（需客户 JWT，blob 带上传者标记）；
#                    创建评论时 images: [signed_id] 只接受本人上传，≤3 张，非法 signed_id 被拒
RSpec.describe 'Product review photos', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }
  let(:uploads_path) { '/api/v3/store/direct_uploads' }

  # 真实写入测试存储：未上传的 blob（create_before_direct_upload!）在 attach 时读不到文件
  def build_blob(content_type: 'image/jpeg', byte_size: 1024, name: 'photo.jpg')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('x' * byte_size),
      filename: name,
      content_type: content_type
    )
  end

  # 模拟客户经预签端点上传后的 blob（带上传者标记）
  def owned_blob(uploader: user, **options)
    blob = build_blob(**options)
    blob.update!(metadata: blob.metadata.merge(PallasTrade::Review::IMAGE_UPLOADER_METADATA_KEY => uploader.id))
    blob
  end

  describe 'POST /api/v3/store/direct_uploads (AC-004)' do
    it 'presigns an upload and tags the blob with the customer' do
      post uploads_path,
           params: { blob: { filename: 'pic.jpg', byte_size: 2048, checksum: Digest::MD5.base64digest('pic'), content_type: 'image/jpeg' } },
           headers: headers

      expect(response).to have_http_status(:created)
      blob = ActiveStorage::Blob.find_signed!(json_response['signed_id'])
      expect(blob.metadata[PallasTrade::Review::IMAGE_UPLOADER_METADATA_KEY]).to eq(user.id)
      expect(json_response['direct_upload']['url']).to be_present
    end

    it 'requires a customer JWT' do
      post uploads_path,
           params: { blob: { filename: 'pic.jpg', byte_size: 2048, checksum: Digest::MD5.base64digest('pic'), content_type: 'image/jpeg' } },
           headers: api_key_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'attaching photos when creating a review (AC-004)' do
    it 'attaches up to three photos the customer uploaded' do
      blobs = Array.new(3) { |index| owned_blob(name: "photo-#{index}.jpg") }

      post path, params: { rating: 5, title: 'With photos', images: blobs.map(&:signed_id) }, headers: headers

      expect(response).to have_http_status(:created)
      review = PallasTrade::Review.for_store(store).last
      expect(review.images.count).to eq(3)
      expect(Array(json_response[:image_urls]).size).to eq(3)
    end

    it 'rejects more than three photos' do
      blobs = Array.new(4) { |index| owned_blob(name: "photo-#{index}.jpg") }

      post path, params: { rating: 5, images: blobs.map(&:signed_id) }, headers: headers

      expect(response).to have_http_status(422)
      expect(json_response[:error][:code]).to eq('review_image_limit_exceeded')
      expect(PallasTrade::Review.for_store(store).count).to eq(0)
    end

    it 'rejects a blob another customer uploaded' do
      stranger_blob = owned_blob(uploader: create(:user), name: 'stranger.jpg')

      post path, params: { rating: 5, images: [stranger_blob.signed_id] }, headers: headers

      expect(response).to have_http_status(422)
      expect(json_response[:error][:code]).to eq('review_image_not_owned')
      expect(PallasTrade::Review.for_store(store).count).to eq(0)
    end

    it 'rejects a tampered signed id' do
      post path, params: { rating: 5, images: ['not-a-real-signed-id'] }, headers: headers

      expect(response).to have_http_status(422)
      expect(json_response[:error][:code]).to eq('review_image_invalid')
    end
  end

  describe 'model limits (AC-001)' do
    let(:review) { build(:review, store: store, product: product, user: user, rating: 4) }

    it 'rejects an unsupported content type' do
      review.images.attach(build_blob(content_type: 'application/pdf', name: 'doc.pdf'))

      expect(review).not_to be_valid
      expect(review.errors[:images]).to include('must be a JPEG, PNG or WebP image')
    end

    it 'rejects a photo larger than five megabytes' do
      review.images.attach(build_blob(byte_size: 6.megabytes, name: 'huge.jpg'))

      expect(review).not_to be_valid
      expect(review.errors[:images]).to include('must be 5MB or smaller')
    end

    it 'accepts three jpeg photos' do
      Array.new(3) { |index| review.images.attach(build_blob(name: "ok-#{index}.jpg")) }

      expect(review).to be_valid
    end
  end
end
