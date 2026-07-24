require 'rails_helper'

RSpec.describe PallasTrade::Images::SaveFromUrlJob, type: :job do
  subject(:job) { described_class.new }

  let(:attachment) { double(:attachment) }
  let(:image) do
    Struct.new(:attachment, :external_url, :external_id) do
      def save!
        true
      end
    end.new(attachment)
  end
  let(:external_url) { 'https://example.com/product.webp' }

  before do
    allow(PallasTrade::Config).to receive(:max_image_download_size).and_return(5.megabytes)
  end

  it 'rejects non-success responses before attaching them' do
    response = Struct.new(:code, :body).new('404', 'not found')
    allow(SsrfFilter).to receive(:get).and_return(response)
    expect(attachment).not_to receive(:attach)

    expect do
      job.send(:download_and_attach_image, external_url, image, nil)
    end.to raise_error(PallasTrade::Images::InvalidRemoteImageError, /HTTP 404/)
  end

  it 'rejects a successful response whose body is not an image' do
    response = Struct.new(:code, :body).new('200', '404: Not Found')
    allow(SsrfFilter).to receive(:get).and_return(response)
    expect(attachment).not_to receive(:attach)

    expect do
      job.send(:download_and_attach_image, external_url, image, nil)
    end.to raise_error(PallasTrade::Images::InvalidRemoteImageError, /not an image/)
  end

  it 'attaches a valid image using its detected content type' do
    body = Rails.root.join('pallastrade_gems/pallastrade_core/spec/fixtures/files/img_256x128.png').binread
    response = Struct.new(:code, :body).new('200', body)
    allow(SsrfFilter).to receive(:get).and_return(response)
    expect(attachment).to receive(:attach).with(hash_including(filename: 'product.webp', content_type: 'image/png'))

    job.send(:download_and_attach_image, external_url, image, nil)

    expect(image.external_url).to eq(external_url)
  end

  it 'loads packaged sample images without making a network request' do
    sample_url = 'pallastrade-sample://demo-images/automatic-espresso-machine-silver.webp'
    expect(SsrfFilter).not_to receive(:get)

    response = job.send(:fetch_image, sample_url)

    expect(response.code).to eq('200')
    expect(Marcel::MimeType.for(StringIO.new(response.body))).to eq('image/webp')
  end

  it 'prevents traversal outside the packaged sample image directory' do
    sample_url = 'pallastrade-sample://demo-images/../products.csv'

    expect do
      job.send(:fetch_image, sample_url)
    end.to raise_error(PallasTrade::Images::InvalidRemoteImageError, /Invalid packaged sample image URL/)
  end
end
