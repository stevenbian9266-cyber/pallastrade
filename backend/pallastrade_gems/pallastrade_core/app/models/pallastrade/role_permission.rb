# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: 角色权限（2026-08-16 权限体系重构）
  #
  # 后台角色权限由 DB 驱动（取代代码级 `PallasTrade.permissions.assign` 的
  # admin 角色配置）。一条 RolePermission 表示：
  #   - set      → 引用权限集类（permission_set，如 SuperUser），保留复杂块逻辑
  #   - function → 资源 × 操作（resource + action: read/create/update/destroy/export/manage）
  #   - menu     → 导航项可见性（nav_key + allowed）
  #   - data     → 数据范围（resource + scope: all/self/store/channel/custom）
  #
  # `allowed=false` 用于显式拒绝（覆盖同一资源更宽泛的授予）。
  class RolePermission < PallasTrade.base_class
    has_prefix_id :rolperm

    PERMISSION_TYPES = %w[set function menu data].freeze
    FUNCTION_ACTIONS = %w[read create update destroy export manage].freeze
    DATA_SCOPES = %w[all self store channel custom].freeze

    belongs_to :role, class_name: 'PallasTrade::Role'

    validates :role, presence: true
    validates :permission_type, inclusion: { in: PERMISSION_TYPES }
    validates :permission_set, presence: true, if: -> { permission_type == 'set' }
    validates :nav_key, presence: true, if: -> { permission_type == 'menu' }
    validates :resource, presence: true, if: -> { %w[function data].include?(permission_type) }
    validates :action, presence: true, inclusion: { in: FUNCTION_ACTIONS }, if: -> { permission_type == 'function' }
    validates :scope, presence: true, inclusion: { in: DATA_SCOPES }, if: -> { permission_type == 'data' }

    scope :menu, -> { where(permission_type: 'menu') }
    scope :function, -> { where(permission_type: 'function') }
    scope :data, -> { where(permission_type: 'data') }
    scope :set, -> { where(permission_type: 'set') }
    scope :allowed, -> { where(allowed: true) }
  end
end
