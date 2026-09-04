# frozen_string_literal: true

module PallasTrade
  # P0-6 (PRD FR-064): 审计写入服务。
  #
  # 统一入口，供 Webhook Replay / Manual Payment Repair / Refund / Gateway
  # Credential Change 等敏感操作调用。写失败绝不影响主流程（rescue → Rails.error）。
  #
  # 用法：
  #   PallasTrade::Audit.record(
  #     actor: { type: 'PallasTrade::User', id: user.id },   # 或 actor: 'system'
  #     action: 'webhook_replay',
  #     resource: webhook_event,                              # AR record → type/id/prefixed
  #     before: {...}, after: {...}, metadata: {...}
  #   )
  module Audit
    module_function

    # @param action [String, Symbol]
    # @param opts [Hash] actor / resource / resource_type / resource_id /
    #   request_id / before / after / metadata（见类注释用法）
    # @return [PallasTrade::AuditLog, nil] 创建成功返回记录；失败返回 nil（不抛）
    def record(action:, **opts)
      actor = opts[:actor]
      resource = opts[:resource]
      request_id = opts[:request_id]
      before = opts[:before]
      after = opts[:after]
      metadata = opts[:metadata]

      actor_type, actor_id, actor_label = normalize_actor(actor)
      res_type = opts[:resource_type] || resource&.class&.name
      res_id = opts[:resource_id] || resource&.id
      res_prefixed = resource.respond_to?(:prefixed_id) ? resource.prefixed_id : nil

      PallasTrade::AuditLog.create!(
        actor_type: actor_type,
        actor_id: actor_id,
        actor_label: actor_label,
        action: action.to_s,
        resource_type: res_type,
        resource_id: res_id,
        resource_prefixed_id: res_prefixed,
        request_id: request_id || current_request_id,
        before: before,
        after: after,
        metadata: metadata,
        occurred_at: Time.current
      )
    rescue StandardError => e
      Rails.error.report(e, context: { action: action.to_s }, source: 'PallasTrade.audit')
      nil
    end

    def normalize_actor(actor)
      case actor
      when Hash
        [actor[:type] || actor['type'], actor[:id] || actor['id'], actor[:label] || actor['label']]
      when String, Symbol
        [nil, nil, actor.to_s]
      else
        [actor&.class&.name, actor&.id, nil]
      end
    end
    private_class_method :normalize_actor

    def current_request_id
      Thread.current[:pallastrade_request_id]
    end
    private_class_method :current_request_id
  end
end
