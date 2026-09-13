# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-7 (PRD-20260913-payments-dsp-p7-7-admin-disputes-console)
#
# Admin Dispute Ops —— 争议域控制台（Orders → Disputes；源计划 §66 展现面 / §67 动作集）。
#
# index：store 作用域争议列表（`Dispute.for_store` + Ransack 白名单 + 表格注册 `:disputes`）。
# show ：§66 全字段下钻（关联 / provider 引用 / journal / 对账 / 证据快照 / 收敛状态 / 最近 provider 事件）；
#        在线只读调用（对账、证据投影、裁决）**逐个降级**，异常一律 nil → 页面**恒 200**（对齐 RefundsOpsController#show）。
#
# 动作（全部幂等；危险操作不在本切片）：
#   refresh     = 刷新 provider 状态（`ResolveFact(fetch: true)`，**只读**）
#   dry_run     = 收敛预览（`Recover(apply: false)`，**零写**）
#   recover     = 收敛执行（`Recover(apply: true)`，唯一允许的写；幂等，重复执行 `noop`）
#   snapshot    = 生成证据快照（`BuildEvidenceSnapshot(fetch: true)`，**transient 不落库、不提交**）
#   mark_review = 人工标记复核（attention + manual_review + 审计 actor）
#
# 铁律（源计划 §49/§50/§67）：不退款、不重扣、不建 Payment、不改 order/inventory/journal、
#   不调 provider 写方法；`Accept Dispute` / `Submit Evidence` **不在本切片**（归 P7-8，需 permission + confirmation + audit）。
module PallasTrade
  module Admin
    class DisputesOpsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # 自定义动作名不是 CanCan 真实动作（无法 alias 到 :update）→ 跳过基类 `load_resource`
      # （它用**原始 action 名**对实例授权），改为自加载记录 + 在 `authorize_admin` 里映射语义动作。
      CUSTOM_ACTIONS = %i[refresh dry_run recover snapshot mark_review].freeze
      # 写动作（映射到 :update；其余自定义动作归 :read）
      UPDATE_ACTIONS = %i[recover mark_review].freeze
      # 「最近 provider 事件」候选窗口（有界扫描，零 provider I/O；命中失败显示 —）
      PROVIDER_EVENT_WINDOW = 20

      skip_before_action :load_resource, only: CUSTOM_ACTIONS
      before_action :load_dispute, only: CUSTOM_ACTIONS

      # GET /admin/disputes
      def index
        super
      end

      # GET /admin/disputes/:id —— §66 全字段下钻（在线只读调用逐个降级，页面恒 200）
      def show
        dispute = @dispute || @object
        @fact = safe_value { PallasTrade::Disputes::ResolveFact.call(dispute: dispute) }
        @reconciliation = safe_value { PallasTrade::Reconciliations::ReconcileDispute.call(dispute: dispute) }
        @evidence = safe_value { PallasTrade::Disputes::BuildEvidenceSnapshot.call(dispute: dispute) }
        @evidence_sections = evidence_sections_for(@evidence)
        @journal_entries = journal_entries_for(dispute)
        @refunds = refunds_for(dispute)
        @recovery = recovery_metadata(dispute)
        @last_provider_event = last_provider_event(dispute)
      end

      # POST /admin/disputes/:id/refresh —— 刷新 provider 状态（只读契约，零写）
      def refresh
        outcome = PallasTrade::Disputes::ResolveFact.call(dispute: @dispute, fetch: true)
        if outcome.success?
          fact = outcome.value
          flash[:success] = PallasTrade.t('admin.orders.disputes_refreshed',
                                          resolution: fact.resolution,
                                          provider_status: fact.provider_status.presence || '—')
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.disputes_refresh_failed')
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/dry_run —— 收敛预览（零写）
      def dry_run
        outcome = PallasTrade::Disputes::Recover.call(dispute: @dispute, fetch: true, apply: false)
        if outcome.success?
          flash[:success] = PallasTrade.t('admin.orders.disputes_dry_run_done', decision: outcome.value[:decision])
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.disputes_dry_run_failed')
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/recover —— 幂等收敛（唯一允许的写；重复执行 noop）
      def recover
        outcome = PallasTrade::Disputes::Recover.call(dispute: @dispute, fetch: true, apply: true)
        if outcome.success?
          flash[:success] = PallasTrade.t('admin.orders.disputes_recovered', decision: outcome.value[:decision])
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.disputes_recover_failed')
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/snapshot —— 生成证据快照（transient；不落库、不提交）
      def snapshot
        outcome = PallasTrade::Disputes::BuildEvidenceSnapshot.call(dispute: @dispute, fetch: true)
        if outcome.success?
          flash[:success] = PallasTrade.t('admin.orders.disputes_snapshot_done',
                                          missing: outcome.value.missing_evidence.size)
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.disputes_snapshot_failed')
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/mark_review —— 人工标记复核（attention + manual_review + 审计）
      def mark_review
        outcome = PallasTrade::Disputes::MarkManualReview.call(dispute: @dispute, actor: audit_actor)
        if outcome.success?
          key = outcome.value[:already_marked] ? 'disputes_already_marked' : 'disputes_marked_review'
          flash[:success] = PallasTrade.t("admin.orders.#{key}")
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.disputes_mark_review_failed')
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      private

      def model_class
        PallasTrade::Dispute
      end

      # `ResourceController` 默认用 `controller_name.singularize`（→ `disputes_op`）→ 必须显式声明，
      # 否则 `@disputes_op` 实例变量与 `admin_dispute_path` helper 全部失效
      def object_name
        'dispute'
      end

      def collection_includes
        [:payment, :order]
      end

      def collection_default_sort
        'created_at desc'
      end

      # 自定义动作名 → 语义动作（绕过基类原始动作名授权后，这里仍是唯一授权口）
      def authorize_admin
        authorize! :admin, model_class
        authorize! UPDATE_ACTIONS.include?(action) ? :update : :read, model_class
      end

      # 与基类 `find_resource` 同语义（store 作用域 + prefixed id），供自定义动作使用
      def load_dispute
        @dispute = model_class.for_store(current_store).find_by_prefix_id!(params[:id])
      end

      # 审计 actor（对齐 RefundsOpsController）：当前后台用户 → { type, id, label }，否则 'admin'
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      # 在线只读调用：成功取 value，失败/异常一律降级 nil（页面永不 500）
      def safe_value
        outcome = yield
        outcome.success? ? outcome.value : nil
      rescue StandardError
        nil
      end

      def journal_entries_for(dispute)
        PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).order(:effective_at, :id)
      rescue StandardError
        []
      end

      # 证据快照分段 → 视图友好的数组（availability/reason 兼容 symbol 与 string 键）
      def evidence_sections_for(evidence)
        return [] if evidence.nil?

        sections = evidence.sections
        return [] unless sections.respond_to?(:map)

        sections.map do |name, section|
          { name: name.to_s.humanize,
            availability: section[:availability] || section['availability'],
            reason: section[:reason] || section['reason'] }
        end
      rescue StandardError
        []
      end

      # Refund overlap（只读）：同一 payment 下的退款队列
      def refunds_for(dispute)
        payment_id = dispute.payment_id
        return [] if payment_id.nil?

        PallasTrade::Refund.where(payment_id: payment_id).order(created_at: :desc).limit(20)
      rescue StandardError
        []
      end

      # P7-6 收敛审计（最近一次；仅展示，不解释）
      def recovery_metadata(dispute)
        metadata = dispute.private_metadata
        metadata.is_a?(Hash) ? metadata['recovery'] : nil
      end

      # 最近一次入站 dispute 事件（有界扫描同 payment_method 的 dispute 事件窗口；
      # 找不到则显示 —，**不**做全表 JSON 扫描）
      def last_provider_event(dispute)
        payment_method_id = dispute.payment&.payment_method_id
        return nil if payment_method_id.nil?

        reference = dispute.provider_dispute_reference.to_s
        window = PallasTrade::PaymentWebhookEvent.
                 where(payment_method_id: payment_method_id).
                 where(action: PallasTrade::PaymentWebhookEvent::DISPUTE_ACTIONS).
                 order(created_at: :desc).
                 limit(PROVIDER_EVENT_WINDOW)

        window.find { |event| event.payload.to_s.include?(reference) }
      rescue StandardError
        nil
      end
    end
  end
end
