# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B1
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # EvidenceAssets —— 证据**素材库**读写门面（FR-001）。
    #
    # 职责边界（对齐 `EvidenceCatalog` 的纯函数范式）：
    #   - `list` / `suggest` / `insert`：**零写、零 I/O、零 provider**；
    #   - `create` / `retire`：只写素材表本身（+审计），**不**触碰 Dispute / Payment / 回执 / 库存 / 订单；
    #   - **不提供任何提交入口** —— 提交唯一入口仍是 `Disputes::SubmitEvidence`（需显式确认）。
    class EvidenceAssets
      MAX_SUGGESTIONS = 20

      # @param store [PallasTrade::Store, nil]
      def initialize(store: nil)
        @store = store
      end

      # 只读列举（默认只列 active）。
      def list(kind: nil, reason_code: nil, evidence_key: nil, include_inactive: false)
        scope = base_scope.by_kind(kind).for_reason_code(reason_code).for_evidence_key(evidence_key)
        scope = scope.active_only unless include_inactive
        scope.recent_first
      end

      # 入库素材（唯一写入口之一；审计留痕，零资金副作用）。
      # @return [Hash] { ok:, asset:, errors: [codes] }
      def create(name:, kind: 'text', body: nil, reason_code: nil, evidence_key: nil, file: nil, actor: 'admin')
        asset = PallasTrade::DisputeEvidenceAsset.new(
          store: @store,
          name: name.to_s.strip,
          kind: kind.to_s,
          body: body,
          reason_code: reason_code.presence&.to_s,
          evidence_key: evidence_key.presence&.to_s,
          active: true,
          created_by: actor_label(actor)
        )
        asset.file.attach(file) if file.present? && asset.respond_to?(:file)

        return { ok: false, asset: asset, errors: asset.errors.full_messages.map { |m| "asset_invalid:#{m}" } } unless asset.save

        audit('dispute_evidence_asset_created', asset, actor)
        { ok: true, asset: asset, errors: [] }
      end

      # 停用素材（软删；保留审计与历史引用）。
      def retire(asset:, actor: 'admin')
        return { ok: false, asset: nil, errors: ['asset_not_found'] } if asset.nil?

        asset.update!(active: false)
        audit('dispute_evidence_asset_retired', asset, actor)
        { ok: true, asset: asset, errors: [] }
      end

      # 引用素材 → 返回**纯值**（草稿填充用）。
      # 关键：不调 provider、不建回执、不改任何状态 —— 人工确认后仍须走 SubmitEvidence。
      def insert(asset:)
        return { ok: false, errors: ['asset_not_found'] } if asset.nil?
        return { ok: false, errors: ['asset_inactive'] } unless asset.active

        value = asset.value
        return { ok: false, errors: ['asset_value_missing'] } if blank_value?(value)

        { ok: true, key: asset.evidence_key, value: value, asset_id: asset.prefixed_id, errors: [] }
      end

      # 按 provider 证据目录 + 争议上下文**建议**素材（FR-002：只建议，绝不生成/提交）。
      # 无契约（catalog 不支持）→ 返回空建议 + unsupported 标记，**不编造**。
      def suggest(dispute:, catalog: nil)
        catalog ||= begin
          payment_method = dispute&.payment&.payment_method
          payment_method && EvidenceCatalog.new(payment_method: payment_method)
        end
        return { supported: false, suggestions: [], reason_code: nil } if catalog.nil? || !catalog.supported?

        reason_code = reason_code_for(dispute)
        library = list(reason_code: reason_code, include_inactive: false).limit(MAX_SUGGESTIONS * 4).to_a
        global = list(include_inactive: false).limit(MAX_SUGGESTIONS * 4).to_a
        pool = (library + global).uniq(&:id)

        suggestions = catalog.entries.filter_map do |entry|
          matches = pool.select { |a| a.evidence_key == entry.key || a.kind == entry.type }
          matches = pool.select { |a| a.kind == entry.type } if matches.empty?
          next if matches.empty?

          {
            key: entry.key,
            type: entry.type,
            required: entry.required,
            assets: matches.first(3).map { |a| { id: a.prefixed_id, name: a.name, kind: a.kind } }
          }
        end.first(MAX_SUGGESTIONS)

        { supported: true, reason_code: reason_code, suggestions: suggestions }
      end

      # 争议的 reason code（provider 归一化字段优先，其次私有元数据；缺失即 nil，不猜）
      def reason_code_for(dispute)
        return nil if dispute.nil?

        %w[reason_code reason].each do |field|
          value = dispute.respond_to?(field) ? dispute.public_send(field) : nil
          return value.to_s if value.present?
        end
        metadata = dispute.respond_to?(:private_metadata) ? dispute.private_metadata : nil
        return nil unless metadata.is_a?(Hash)

        metadata['reason_code'] || metadata['reason'] || metadata['provider_reason']
      end

      private

      def base_scope
        PallasTrade::DisputeEvidenceAsset.for_store(@store)
      end

      # 值有效性：文本 → 非空字符串；文件 → 必须**已附加**
      # （`has_one_attached` 未附加时返回代理对象：既非 nil、也不响应 `empty?` —— 必须显式判 `attached?`）
      def blank_value?(value)
        return true if value.nil?
        return true if value.respond_to?(:attached?) && !value.attached?
        return value.empty? if value.respond_to?(:empty?)

        false
      end

      def audit(action, asset, actor)
        PallasTrade::Audit.record(
          action: action,
          actor: actor,
          resource: asset,
          after: { asset: asset.prefixed_id, name: asset.name, kind: asset.kind, active: asset.active }
        )
      rescue StandardError
        nil # 审计失败不影响素材本身（与既有服务的降级取向一致）
      end

      def actor_label(actor)
        return actor[:label].to_s if actor.is_a?(Hash) && actor.key?(:label)
        return actor['label'].to_s if actor.is_a?(Hash) && actor.key?('label')

        actor.to_s
      end
    end
  end
end
