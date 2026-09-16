# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# Admin 结算台账（Orders → 结算台账）：
#   * index：按 provider / 状态 / 到账日筛选 + 汇总（gross/fee/net）+ 分页；
#   * show：批次事实 + 明细行（kind/引用/金额/匹配状态/本地引用）+ 「重新匹配」动作；
#   * new / import：粘贴或上传 provider 结算报表（CSV）→ 导入 + 自动匹配 + 差异进队列。
#
# 铁律：导入/匹配/入队只写台账表 + 案例表 + 审计（零资金副作用；不调 provider）。
module PallasTrade
  module Admin
    class PayoutsController < BaseController
      PER_PAGE = 50

      before_action :add_payout_breadcrumbs
      before_action :load_payout, only: %i[show match]

      # GET /admin/payouts
      def index
        @filters = filters
        scope = filtered_scope

        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @payouts = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @providers = base_scope.distinct.pluck(:provider).compact.sort
        @totals = totals_for(scope)
        @difference_counts = difference_counts_for(@payouts)
      end

      # GET /admin/payouts/:id
      def show
        @lines = @payout.lines.order(:kind, :provider_reference).to_a
        @line_counts = @payout.lines.group(:match_status).count
        @audits = safe_value { audits_for(@payout) } || []
      end

      # GET /admin/payouts/new —— 导入表单
      def new
        @providers = base_scope.distinct.pluck(:provider).compact.sort
      end

      # POST /admin/payouts/import —— 导入 + 匹配 + 差异进队列
      def import
        outcome = PallasTrade::Reconciliations::Payouts::ImportCSV.call(
          store: current_store,
          provider: params[:provider],
          csv: csv_payload,
          source: params[:source].presence || imported_source,
          actor: audit_actor
        )

        if outcome.success?
          match_payouts(outcome.value[:payouts])
          flash[:success] = PallasTrade.t(
            'admin.payouts.import_success',
            payouts: outcome.value[:payouts].size,
            created: outcome.value[:lines_created],
            skipped: outcome.value[:lines_skipped],
            errors: outcome.value[:errors].size
          )
          flash[:warning] = PallasTrade.t('admin.payouts.import_errors', rows: import_error_rows(outcome.value[:errors])) if outcome.value[:errors].any?
          redirect_to PallasTrade.admin_payouts_path, status: :see_other
        else
          flash[:error] = "#{PallasTrade.t('admin.payouts.import_failed')}: #{outcome.error}"
          redirect_to PallasTrade.new_admin_payout_path, status: :see_other
        end
      end

      # POST /admin/payouts/:id/match —— 重新匹配（幂等；差异行进队列 / 已匹配行销案）
      def match
        authorize! :update, @payout
        outcome = PallasTrade::Reconciliations::Payouts::Match.call(payout: @payout, actor: audit_actor)

        if outcome.success?
          PallasTrade::Reconciliations::Payouts::SyncCases.call(payout: @payout)
          flash[:success] = PallasTrade.t(
            'admin.payouts.match_success',
            matched: outcome.value[:matched], unmatched: outcome.value[:unmatched],
            mismatch: outcome.value[:amount_mismatch], status: PallasTrade.t("admin.payouts.status_#{outcome.value[:status]}")
          )
        else
          flash[:error] = "#{PallasTrade.t('admin.payouts.match_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_payout_path(@payout), status: :see_other
      end

      helper_method :payout_status_class, :payout_line_status_class, :payout_amount

      private

      # 授权锚点：`can :manage, PallasTrade::Payout`
      def model_class
        PallasTrade::Payout
      end

      def add_payout_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.payouts.title'), PallasTrade.admin_payouts_path
      end

      def load_payout
        @payout = base_scope.find(params[:id])
      end

      def base_scope
        PallasTrade::Payout.where(store_id: current_store.id)
      end

      def filter_params
        {
          provider: params[:provider].presence,
          status: params[:status].presence,
          from: parse_boundary(params[:from]),
          to: parse_boundary(params[:to], end_of_day: true)
        }
      end

      def filters
        @filters ||= filter_params
      end

      def filtered_scope
        base_scope.filter_by(store_id: current_store.id, **filters)
      end

      def totals_for(scope)
        sums = scope.pick(
          Arel.sql('COALESCE(SUM(gross_total), 0)'),
          Arel.sql('COALESCE(SUM(fee_total), 0)'),
          Arel.sql('COALESCE(SUM(net_total), 0)')
        )
        { gross: sums[0], fee: sums[1], net: sums[2] }
      end

      # 列表页差异行计数（一次聚合查询，避免逐行 N+1）
      def difference_counts_for(payouts)
        ids = Array(payouts).map(&:id)
        return {} if ids.empty?

        PallasTrade::PayoutLine.differences.where(payout_id: ids).group(:payout_id).count
      end

      # 导入入参：文件上传优先，其次粘贴文本。
      def csv_payload
        uploaded = params[:file]
        return uploaded.read if uploaded.respond_to?(:read)

        params[:csv].to_s
      end

      def imported_source
        uploaded = params[:file]
        uploaded.respond_to?(:original_filename) ? uploaded.original_filename.to_s : 'admin_paste'
      end

      def import_error_rows(errors)
        Array(errors).first(10).map { |error| "##{error[:row]} #{error[:message]}" }.join('; ')
      end

      def match_payouts(payout_ids)
        PallasTrade::Payout.where(id: payout_ids).find_each do |payout|
          PallasTrade::Reconciliations::Payouts::Match.call(payout: payout, actor: audit_actor)
          PallasTrade::Reconciliations::Payouts::SyncCases.call(payout: payout)
        end
      end

      def parse_boundary(value, end_of_day: false)
        return nil if value.blank?

        time = Time.zone.parse(value.to_s)
        return nil if time.nil?
        return time unless value.to_s.strip.length <= 10

        end_of_day ? time.end_of_day : time.beginning_of_day
      rescue ArgumentError, TypeError
        nil
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def safe_value
        yield
      rescue StandardError => e
        Rails.logger.warn(
          message: 'admin.payouts.degraded',
          error: e.class.name,
          detail: e.message.to_s.truncate(200)
        )
        nil
      end

      def audits_for(payout)
        PallasTrade::AuditLog
          .where(resource_type: payout.class.name, resource_id: payout.id)
          .order(occurred_at: :desc)
          .limit(20)
          .to_a
      end

      # -- 视图辅助 --

      def payout_status_class(status)
        case status.to_s
        when 'settled' then 'badge-success'
        when 'difference' then 'badge-danger'
        else 'badge-info'
        end
      end

      def payout_line_status_class(status)
        case status.to_s
        when 'matched' then 'badge-success'
        when 'amount_mismatch' then 'badge-warning'
        when 'unmatched' then 'badge-danger'
        else 'badge-secondary'
        end
      end

      # 金额展示（确定性两位小数，避免 BigDecimal#to_s 的格式差异）
      def payout_amount(value)
        return '—' if value.blank?

        format('%.2f', value.to_d)
      end
    end
  end
end
