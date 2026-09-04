# frozen_string_literal: true

module PallasTrade
  module Api
    module Middleware
      # P0-6 (FR-063/FR-064): 为每个 API 请求把 request_id 注入
      # Thread.current[:pallastrade_request_id]，供 AuditLog.request_id 与结构化
      # 支付日志使用（请求结束后清理，防跨请求泄漏）。覆盖 /api/v3 与 webhook 端点。
      class RequestId
        THREAD_KEY = :pallastrade_request_id

        def initialize(app)
          @app = app
        end

        def call(env)
          Thread.current[THREAD_KEY] = resolve_id(env)
          @app.call(env)
        ensure
          Thread.current[THREAD_KEY] = nil
        end

        private

        def resolve_id(env)
          env['HTTP_X_REQUEST_ID'].presence ||
            env['action_dispatch.request_id'].presence ||
            SecureRandom.hex(8)
        end
      end
    end
  end
end
