# frozen_string_literal: true

require 'rails_helper'

# P0-6 (FR-063/FR-064): RequestId 中间件 —— 注入并清理 Thread.current request_id。
RSpec.describe PallasTrade::Api::Middleware::RequestId, type: :request do
  it 'sets the request id for the duration of a request and clears it afterwards' do
    inner = lambda do |_env|
      [200, { 'Content-Type' => 'text/plain' }, [Thread.current[described_class::THREAD_KEY].to_s]]
    end
    app = described_class.new(inner)

    response = Rack::MockRequest.new(app).get('/api/v3/store/carts/x')

    expect(response.status).to eq(200)
    expect(response.body).to be_present
    expect(Thread.current[described_class::THREAD_KEY]).to be_nil
  end

  it 'prefers an inbound X-Request-Id header' do
    inner = lambda do |_env|
      [200, { 'Content-Type' => 'text/plain' }, [Thread.current[described_class::THREAD_KEY].to_s]]
    end
    app = described_class.new(inner)

    response = Rack::MockRequest.new(app).get('/api/v3', 'HTTP_X_REQUEST_ID' => 'req-abc-123')

    expect(response.body).to eq('req-abc-123')
  end
end
