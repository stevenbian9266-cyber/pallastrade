# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-7 (PRD-20260913-payments-dsp-p7-7-admin-disputes-console)
#
# Admin Dispute Ops —— 争议域控制台（Orders → Disputes；源计划 §66 展现面 / §67 动作集）。
#
# index：store 作用域争议列表（`Dispute.for_store` + Ransack 白名单 + 表格注册 `:disputes`）。
# show ：§66 全字段下钻（关联 / provider 引用 / journal / 对账 / 证据快照 / 收敛状态 / 最近 provider 事件）；
#        在线只读调用（对账、证据投影、裁决）**逐个降级**，异常一律 nil → 页面**恒 200**（对齐 RefundsOpsController#show）。
#
# 动作（P7-7 全部安全；P7-8 新增两个**危险操作**）：
#   refresh         = 刷新 provider 状态（`ResolveFact(fetch: true)`，**只读**）
#   dry_run         = 收敛预览（`Recover(apply: false)`，**零写**）
#   recover         = 收敛执行（`Recover(apply: true)`，本地唯一写；幂等）
#   snapshot        = 生成证据快照（`BuildEvidenceSnapshot(fetch: true)`，**transient 不落库、不提交**）
#   mark_review     = 人工标记复核（attention + manual_review + 审计 actor）
#   submit_evidence = **危险**：向 provider 提交证据（Stripe Dispute#update；需 permission + confirmation + audit）
#   accept_dispute  = **危险且不可逆**：接受争议（Stripe Dispute#close；需 permission + confirmation + audit）
#
# 铁律（源计划 §49/§50/§67）：不退款、不重扣、不建 Payment、不改 order/inventory/journal、
#   **危险操作只调 provider 写 + 落不可变回执**（资金结果仍由 webhook 驱动 P7-3 入账 / P7-6 收敛）。
module PallasTrade
  module Admin
    class DisputesOpsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # 自定义动作名不是 CanCan 真实动作（无法 alias 到 :update）→ 跳过基类 `load_resource`
      # （它用**原始 action 名**对实例授权），改为自加载记录 + 在 `authorize_admin` 里映射语义动作。
      CUSTOM_ACTIONS = %i[refresh dry_run recover snapshot mark_review precheck approve_draft submit_evidence accept_dispute].freeze
      # 写动作（映射到 :update；其余自定义动作归 :read）
      UPDATE_ACTIONS = %i[recover mark_review approve_draft submit_evidence accept_dispute].freeze
      # 「最近 provider 事件」候选窗口（有界扫描，零 provider I/O；命中失败显示 —）
      PROVIDER_EVENT_WINDOW = 20

      skip_before_action :load_resource, only: CUSTOM_ACTIONS
      before_action :load_dispute, only: CUSTOM_ACTIONS

      # GET /admin/disputes
      # DSP-P7-10 B2：列表页附**只读运营报表**（默认 90 天窗口；失败降级 nil，列表页恒 200）
      def index
        super
        @ops_report = ops_report_for
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

        # DSP-P7-8：危险操作区的渲染输入（目录 + 最近回执；在线调用全部降级）
        @evidence_catalog = evidence_catalog_for(dispute)
        @evidence_submissions = evidence_submissions_for(dispute)
        @last_acceptance = @evidence_submissions.find { |s| s.kind == 'accepted' }
        @late_submission = late_submission?(dispute)

        # DSP-P7-10 B1：素材库 / provider 建议 / 提交历史（全部只读，逐项降级）
        @evidence_assets = evidence_assets_for
        @evidence_suggestions = evidence_suggestions_for(dispute, @evidence_catalog)
        @submission_timeline = submission_timeline_for(dispute)

        # DSP-P7-10 B2：双人复核（开关 + 签核记录）
        @evidence_review_required = evidence_review_required?
        @evidence_approvals = evidence_approvals_for(dispute)

        # DSP-P7-9：只读能力矩阵 + 支付级多争议聚合（逐项 rescue 降级，页面绑不 500）
        @provider_capabilities = provider_capabilities_for(dispute)
        @payment_summary = payment_summary_for(dispute)
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

      # POST /admin/disputes/:id/precheck —— 提交前完整性/合规校验（DSP-P7-10 B1）
      # **零写**：不建回执、不写审计、不发事件、不调 provider；只把阻断项/建议提示回控制台。
      def precheck
        outcome = PallasTrade::Disputes::PreSubmitCheck.call(
          dispute: @dispute,
          evidence: evidence_payload,
          accept_late: params[:accept_late].present? || params[:late_confirmed].to_s == '1'
        )
        report = outcome.success? ? outcome.value : { ok: false, blocking: ['precheck_unavailable'], warnings: [] }

        if report[:ok]
          flash[:success] = PallasTrade.t('admin.orders.disputes_precheck_ok', count: report[:provided_keys].size)
        else
          reasons = report[:blocking].map { |code| evidence_error_message(code) }.join(' · ')
          flash[:error] = PallasTrade.t('admin.orders.disputes_precheck_blocked', reasons: reasons)
        end
        if report[:warnings].present?
          flash[:warning] = PallasTrade.t('admin.orders.disputes_precheck_warnings',
                                          warnings: report[:warnings].map { |code| evidence_error_message(code) }.join(' · '))
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

      # POST /admin/disputes/:id/approve_draft —— 证据草稿**双人复核**签核（DSP-P7-10 B2 / FR-005）
      # 局部写：只落不可变签核记录 + 审计；**不**提交凭据、**不**建回执、**不**调 provider。
      def approve_draft
        outcome = PallasTrade::Disputes::ApproveEvidenceDraft.call(
          dispute: @dispute,
          actor: audit_actor,
          evidence: evidence_payload,
          decision: params[:decision].presence || 'approved',
          note: params[:note],
          requested_by: params[:requested_by]
        )

        if outcome.success?
          key = outcome.value[:idempotent] ? 'disputes_approve_already_done' : 'disputes_approved_draft'
          flash[:success] = PallasTrade.t("admin.orders.#{key}")
        else
          flash[:error] = evidence_error_message(outcome.error)
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/submit_evidence —— 【危险】向 provider 提交证据
      # 三件套：permission（authorize_admin → :update）+ confirmation（视图 turbo_confirm；逾期需 late_confirmed=1）
      # + audit（服务内 dispute_evidence_submitted / _failed）。
      def submit_evidence
        evidence = params[:evidence].respond_to?(:to_unsafe_h) ? params[:evidence].to_unsafe_h : params[:evidence]
        outcome = PallasTrade::Disputes::SubmitEvidence.call(
          dispute: @dispute,
          evidence: evidence,
          actor: audit_actor,
          accept_late: params[:late_confirmed].to_s == '1',
          require_approval: evidence_review_required?
        )

        if outcome.success?
          value = outcome.value
          key = value[:idempotent] ? 'disputes_evidence_already_submitted' : 'disputes_evidence_submitted'
          flash[:success] = PallasTrade.t("admin.orders.#{key}",
                                          provider_status: value[:provider_status].presence || '—')
        else
          flash[:error] = evidence_error_message(outcome.error)
        end
        redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
      end

      # POST /admin/disputes/:id/accept_dispute —— 【危险且不可逆】接受争议
      # 服务端同样要求显式 `confirm=1`（双重确认：前端 turbo_confirm + 后端参数），确保不是误触。
      def accept_dispute
        unless params[:confirm].to_s == '1'
          flash[:error] = PallasTrade.t('admin.orders.disputes_accept_needs_confirm')
          return redirect_to PallasTrade.admin_dispute_path(@dispute), status: :see_other
        end

        outcome = PallasTrade::Disputes::AcceptDispute.call(
          dispute: @dispute,
          reason: params[:reason],
          actor: audit_actor
        )

        if outcome.success?
          value = outcome.value
          key = value[:idempotent] ? 'disputes_accept_already_done' : 'disputes_accepted'
          flash[:success] = PallasTrade.t("admin.orders.#{key}",
                                          provider_status: value[:provider_status].presence || '—')
        else
          flash[:error] = evidence_error_message(outcome.error)
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

      # DSP-P7-8：provider 证据目录（零 I/O；不支持 → nil → 视图降级为"该网关不支持"）
      def evidence_catalog_for(dispute)
        payment_method = dispute.payment&.payment_method
        return nil if payment_method.nil?

        catalog = PallasTrade::Disputes::EvidenceCatalog.new(payment_method: payment_method)
        catalog.supported? ? catalog : nil
      rescue StandardError
        nil
      end

      # DSP-P7-8：回执列表（最近的在前；异常降级空数组）
      def evidence_submissions_for(dispute)
        PallasTrade::DisputeEvidenceSubmission.for_dispute(dispute).recent_first.limit(20).to_a
      rescue StandardError
        []
      end

      # DSP-P7-10 B1：本店素材库（只读列举；异常降级空数组）
      def evidence_assets_for
        PallasTrade::Disputes::EvidenceAssets.new(store: current_store).list.limit(20).to_a
      rescue StandardError
        []
      end

      # DSP-P7-10 B1：按 provider 契约 + reason code 的**建议**（只建议，绝不生成/提交）
      def evidence_suggestions_for(dispute, catalog)
        PallasTrade::Disputes::EvidenceAssets.new(store: current_store)
                                             .suggest(dispute: dispute, catalog: catalog)
      rescue StandardError
        { supported: false, suggestions: [], reason_code: nil }
      end

      # DSP-P7-10 B1：提交历史 / 版本 / 回执（只读；异常降级 nil）
      def submission_timeline_for(dispute)
        safe_value { PallasTrade::Disputes::SubmissionTimeline.call(dispute: dispute) }
      end

      # DSP-P7-10 B2：本店运营报表（只读、零写；异常降级 nil）
      def ops_report_for
        safe_value { PallasTrade::Disputes::OpsReport.call(store: current_store) }
      end

      # DSP-P7-10 B2 / FR-005：是否要求第二人签核（默认关闭 → 既有提交路径行为不变）
      def evidence_review_required?
        PallasTrade::Config[:dispute_evidence_requires_second_review].present?
      rescue StandardError
        false
      end

      # DSP-P7-10 B2：签核记录（只读；异常降级空数组）
      def evidence_approvals_for(dispute)
        dispute.evidence_approvals.recent_first.limit(10).to_a
      rescue StandardError
        []
      end

      # 草稿载荷（与 submit_evidence 同形：文本 + 上传文件）
      # PALLAS-CUSTOM (2026-09-14, Brakeman MassAssignment / pallastrade-security「禁止 permit!」):
      # 不再 `permit!`（接受任意键并把参数静默标白）。此处只做「参数 → 纯 Hash」转换并剔除
      # 框架保留键；键的合法性由服务层证据目录强制（`EvidenceCatalog#validate` →
      # `unknown_evidence_key:*`），与 submit_evidence 的 `to_unsafe_h` 路径保持一致。
      def evidence_payload
        raw = params[:evidence]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.except('controller', 'action', 'authenticity_token', 'utf8', 'id')
      end

      def late_submission?(dispute)
        dispute.respond_to?(:evidence_due_at) && dispute.evidence_due_at.present? &&
          Time.current > dispute.evidence_due_at
      end

      # DSP-P7-9（FR-P79-08）：provider 能力矩阵（只读、零 I/O；基类 = UNSUPPORTED 形态）。
      # 无 payment 锚点 / 异常 → nil 或降级形态（视图展示原因，不渲染写表单）。
      def provider_capabilities_for(dispute)
        payment_method = dispute.payment&.payment_method
        return nil if payment_method.nil?

        capabilities = if payment_method.respond_to?(:dispute_capabilities)
                         payment_method.dispute_capabilities
                       else
                         { supported: false, reason: 'unsupported_provider' }
                       end
        { provider: dispute.provider, capabilities: capabilities }
      rescue StandardError => e
        Rails.logger.error(
          "[Admin::DisputesOps] capability matrix failed for dispute #{dispute.prefixed_id}: #{e.class} #{e.message}"
        )
        { provider: dispute.provider, capabilities: { supported: false, reason: 'unavailable' } }
      end

      # DSP-P7-9（FR-P79-07）：支付级多争议只读聚合（零写、零 provider I/O；失败降级 nil）
      def payment_summary_for(dispute)
        payment = dispute.payment
        return nil if payment.nil?

        result = PallasTrade::Disputes::PaymentDisputeSummary.call(payment: payment)
        result.success? ? result.value : nil
      rescue StandardError => e
        Rails.logger.error(
          "[Admin::DisputesOps] payment dispute summary failed for dispute #{dispute.prefixed_id}: #{e.class} #{e.message}"
        )
        nil
      end

      # 服务层错误码 → 用户可读文案（未知码原样回显，便于排障）
      def evidence_error_message(error)
        code = error.to_s.split(':').first
        key = "admin.orders.disputes_evidence_error_#{code}"
        message = PallasTrade.t(key)
        message == key ? (error.to_s.presence || PallasTrade.t('admin.orders.disputes_evidence_failed')) : message
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
