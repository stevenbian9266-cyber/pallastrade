# frozen_string_literal: true

module PallasTrade
  # P0-6 (2026-09-03): 敏感操作审计记录（PRD FR-064）。
  #
  # 字段对齐 FR-064：actor_type/actor_id + action + resource_type/resource_id +
  # request_id + before/after + occurred_at。额外冗余 actor_label 与
  # resource_prefixed_id 便于人工/排障查询；before/after 仅存结构化 JSON。
  #
  # 无 has_prefix_id —— 内部审计表，不对外暴露资源 API。
  class AuditLog < PallasTrade.base_class
    validates :action, :occurred_at, presence: true

    scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
    scope :recent, ->(limit = 100) { order(occurred_at: :desc).limit(limit) }
  end
end
