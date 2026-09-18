# frozen_string_literal: true

module PallasTrade
  module Admin
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片3）--
    # 入站 provider webhook 事件运营台（Developers -> Webhook Events；业务方案 §69）。
    #
    # 目标：**排障不再写 SQL** —— 事件流（筛选/分页）+ 详情（payload/解析/关联/错误/耗时）
    # + 安全动作（replay / quarantine / mark_processed，全部写 Audit）。
    #
    # 只读聚合（健康 / 订阅清单）逐个降级：异常一律 nil → 页面恒 200（对齐 disputes_ops 口径）。
    # 本控制器**不做任何业务写**：处置动作只改事件自身的状态壳（可靠性外壳），
    # 业务幂等仍归 `Payments::HandleWebhook`（重放走既有 `ReplayWebhookEvent`）。
    class WebhookEventsController < BaseController
      PER_PAGE = 50

      # 面包屑由导航自动推导（P6）：Developers > Webhook Events。控制器不再手写
      # 模块/子页 crumb（2026-09-18 修复重复层级）。

      # GET /admin/webhook_events
      def index
        @filters = filter_params
        scope = filtered_scope

        @page = [params[:page].to_i, 1].max
        @per_page = PER_PAGE
        @total = scope.count
        @events = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a

        @health = safe_value { PallasTrade::Payments::WebhookHealth.call }
        @checklist = safe_value { PallasTrade::Payments::WebhookSubscriptionChecklist.call }
        @providers = PallasTrade::PaymentWebhookEvent.distinct.pluck(:provider).compact.sort
        @actions = PallasTrade::PaymentWebhookEvent.distinct.pluck(:action).compact.sort
        @statuses = PallasTrade::PaymentWebhookEvent::STATUSES
      end

      # GET /admin/webhook_events/:id
      def show
        @event = find_event
        @order = safe_value { @event.order }
        @payment_session = @event.payment_session
        @audits = safe_value { audits_for(@event) } || []
      end

      # POST /admin/webhook_events/:id/replay -- 复用 P0-2 重放链（含审计 + trace）
      def replay
        event = find_event
        result = PallasTrade::Payments::ReplayWebhookEvent.call(webhook_event: event, actor: audit_actor)
        flash_action_result(result, success_key: 'admin.webhook_events.replayed',
                                     failure_key: 'admin.webhook_events.replay_failed')
        redirect_to PallasTrade.admin_webhook_event_path(event)
      end

      # POST /admin/webhook_events/:id/quarantine -- 隔离（忽略未知事件，保留留痕）
      def quarantine
        event = find_event
        result = PallasTrade::Payments::QuarantineWebhookEvent.call(
          webhook_event: event, reason: params[:reason], actor: audit_actor
        )
        flash_action_result(result, success_key: 'admin.webhook_events.quarantined',
                                     failure_key: 'admin.webhook_events.quarantine_failed')
        redirect_to PallasTrade.admin_webhook_event_path(event)
      end

      # POST /admin/webhook_events/:id/mark_processed -- 人工标记已处理（不重放业务链）
      def mark_processed
        event = find_event
        result = PallasTrade::Payments::MarkWebhookEventProcessed.call(
          webhook_event: event, actor: audit_actor, note: params[:note]
        )
        flash_action_result(result, success_key: 'admin.webhook_events.marked_processed',
                                     failure_key: 'admin.webhook_events.mark_failed')
        redirect_to PallasTrade.admin_webhook_event_path(event)
      end

      helper_method :webhook_event_status_class, :webhook_event_duration, :payload_preview

      private

      # 授权锚点：`can :manage, PallasTrade::PaymentWebhookEvent`（配置管理权限集）。
      def model_class
        PallasTrade::PaymentWebhookEvent
      end

      # 内部表无 prefixed id -> 直接按整数主键加载（不暴露资源 API）。
      def find_event
        PallasTrade::PaymentWebhookEvent.find(params[:id])
      end

      def filter_params
        {
          provider: params[:provider].presence,
          event_action: params[:event_action].presence,
          status: params[:status].presence,
          order_number: params[:order_number].presence,
          from: parse_boundary(params[:from]),
          to: parse_boundary(params[:to], end_of_day: true)
        }
      end

      def filtered_scope
        PallasTrade::PaymentWebhookEvent
          .filter_by(
            provider: @filters[:provider],
            action: @filters[:event_action],
            status: @filters[:status],
            order_number: @filters[:order_number],
            from: @filters[:from],
            to: @filters[:to]
          )
          .order(received_at: :desc, id: :desc)
      end

      # 日期输入（YYYY-MM-DD）：from 取当天 00:00，to 取当天 23:59:59（含当日）。
      def parse_boundary(value, end_of_day: false)
        return nil if value.blank?

        time = Time.zone.parse(value.to_s)
        return nil if time.nil?
        return time unless value.to_s.strip.length <= 10

        end_of_day ? time.end_of_day : time.beginning_of_day
      rescue ArgumentError, TypeError
        nil
      end

      # 与 disputes_ops / payment_methods / refunds_ops 同口径的审计 actor 构造。
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def flash_action_result(result, success_key:, failure_key:)
        if result.success?
          flash[:success] = PallasTrade.t(success_key)
        else
          error = result.error
          detail = error.respond_to?(:message) ? error.message : error.to_s
          flash[:error] = "#{PallasTrade.t(failure_key)}: #{detail}"
        end
      end

      def safe_value
        yield
      rescue StandardError => e
        Rails.logger.warn(
          message: 'admin.webhook_events.degraded',
          error: e.class.name,
          detail: e.message.to_s.truncate(200)
        )
        nil
      end

      def audits_for(event)
        PallasTrade::AuditLog
          .where(resource_type: event.class.name, resource_id: event.id)
          .order(occurred_at: :desc)
          .limit(10)
          .to_a
      end

      # -- 视图辅助（徽章 / 耗时 / payload 预览）--

      def webhook_event_status_class(status)
        case status.to_s
        when 'processed' then 'badge-success'
        when 'failed' then 'badge-danger'
        when 'quarantined' then 'badge-warning'
        else 'badge-info'
        end
      end

      def webhook_event_duration(event)
        seconds = event.processing_duration_seconds
        return '-' if seconds.nil?

        seconds < 1 ? "#{(seconds * 1000).round} ms" : "#{seconds.round(2)} s"
      end

      def payload_preview(event)
        payload = event.payload
        return '-' if payload.blank?

        payload.is_a?(Hash) ? payload.to_json.truncate(4000) : payload.to_s.truncate(4000)
      end
    end
  end
end
