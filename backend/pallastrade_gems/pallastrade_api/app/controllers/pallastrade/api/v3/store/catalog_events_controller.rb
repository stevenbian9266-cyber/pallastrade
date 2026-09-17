# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        # POST /api/v3/store/catalog_events — 前台商品事件批量回流
        # （曝光 / 点击 / 加购 / 搜索）。
        #
        # 详见 `docs/prd/catalog/PRD-20260917-catalog-product-events.md`。
        #
        # ⚠️ **配额形状（务必先读）**：`V3::BaseController` 已全局声明
        # `rate_limit to: rate_limit_per_key`（300/60s），其计数键是 **API key**
        # （`by: -> { request.headers['X-PallasTrade-Api-Key'] }`），而 storefront 全店
        # **共用同一个 publishable key** ⇒ 本端点上限 = **300 请求 / 60s / 整店**。
        # 该全局回调是匿名 lambda，子类 `skip_before_action` **无效**，无法在此绕过。
        #
        # 因此本端点按「**重度批量**」设计：前台每次页面浏览最多 flush 一次，
        # 单请求最多 `CatalogEvent::MAX_BATCH_SIZE` 条 —— 请求数随**页面浏览数**增长，
        # 而非随事件数增长。
        #
        # 另外这里**追加**一条按 IP 的限流，避免单个滥用者独占整店预算
        # （两条限流同时生效，取更严者）。
        class CatalogEventsController < Store::BaseController
          # 匿名访客也要能上报（曝光与点击发生在登录之前）
          allow_guest_storefront_access!

          # 单 IP 配额：远低于全店配额，使单个客户端无法耗尽整店的 300/60s。
          PER_IP_LIMIT_PER_WINDOW = 60

          rate_limit to: PER_IP_LIMIT_PER_WINDOW,
                     within: PallasTrade::Api::Config[:rate_limit_window].seconds,
                     store: Rails.cache,
                     by: -> { request.remote_ip },
                     only: [:create],
                     with: RATE_LIMIT_RESPONSE

          # 允许出现在事件对象里的字段。**故意不含 `metadata`** —— 零 PII 要求下
          # 不接受任何自由结构（否则白名单形同虚设）。
          PERMITTED_EVENT_KEYS = %i[
            event_id event_name product_id variant_id list_id list_name position occurred_at
          ].freeze

          # POST /api/v3/store/catalog_events
          def create
            visitor_id = params[:visitor_id].to_s.strip
            if visitor_id.blank?
              return render_error(
                code: ERROR_CODES[:invalid_request],
                message: 'visitor_id is required',
                status: :unprocessable_entity
              )
            end

            events = permitted_events
            if events.empty?
              return render_error(
                code: ERROR_CODES[:invalid_request],
                message: 'events must be a non-empty array',
                status: :unprocessable_entity
              )
            end

            # 超限整批拒收（不做「接受前 N 条」的部分写入，避免调用方以为全成功）
            if events.size > PallasTrade::CatalogEvent::MAX_BATCH_SIZE
              return render_error(
                code: ERROR_CODES[:invalid_request],
                message: "events exceeds maximum batch size of #{PallasTrade::CatalogEvent::MAX_BATCH_SIZE}",
                status: :unprocessable_entity
              )
            end

            unknown = events.map { |event| event[:event_name].to_s }
                            .reject { |name| PallasTrade::CatalogEvent::EVENT_NAMES.include?(name) }
                            .uniq
            if unknown.any?
              return render_error(
                code: ERROR_CODES[:invalid_request],
                message: "unknown event_name: #{unknown.sort.join(', ')}",
                status: :unprocessable_entity
              )
            end

            received = PallasTrade::CatalogEvents::Record.call(
              store: current_store,
              events: events,
              visitor_id: visitor_id
            )

            render json: { received: received }, status: :created
          end

          private

          # v3 使用扁平参数（`wrap_parameters false`）；顶层 `visitor_id`，
          # `events` 为对象数组。
          def permitted_events
            Array(params.permit(events: PERMITTED_EVENT_KEYS)[:events]).map do |event|
              event.is_a?(ActionController::Parameters) ? event.to_h.symbolize_keys : event.to_h.symbolize_keys
            rescue StandardError
              {}
            end
          end
        end
      end
    end
  end
end
