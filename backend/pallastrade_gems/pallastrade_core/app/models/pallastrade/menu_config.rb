# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: 可视化菜单配置覆盖层（2026-08-16）
  #
  # store_id 为 nil = 全局默认配置；store_id 非 nil = 店铺覆盖配置。
  # 基于导航配置文件（pallastrade_admin_navigation.rb）的默认树作为基线，
  # MenuConfig 作为覆盖层叠加（不破坏 landing/tabs/i18n/面包屑推导）。
  #
  # item_type:
  #   default → 覆盖现有导航项（nav_key = 导航项 key）
  #   custom  → 自定义菜单项（nav_key = 生成的自定义 key，url/icon/parent_key 必填）
  class MenuConfig < PallasTrade.base_class
    has_prefix_id :menucfg

    ITEM_TYPES = %w[default custom].freeze

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true

    validates :nav_key, presence: true
    validates :item_type, inclusion: { in: ITEM_TYPES }
    validates :url, presence: true, if: -> { item_type == 'custom' }
    validates :label, presence: true, if: -> { item_type == 'custom' }
    validate :nav_key_must_exist_in_default_tree, if: -> { item_type == 'default' }

    scope :global, -> { where(store_id: nil) }
    scope :for_store, ->(store) { where(store_id: store&.id) }
    scope :custom, -> { where(item_type: 'custom') }
    scope :default, -> { where(item_type: 'default') }

    # 校验 default 覆盖项的 key 必须存在于默认导航树（P6 单一 sidebar）
    def nav_key_must_exist_in_default_tree
      return if nav_key.blank?

      nav = PallasTrade.admin.navigation.sidebar
      return unless nav

      exists = nav.find(nav_key) || nav.items.values.any? { |item| item.children.any? { |c| c.key.to_s == nav_key } }
      errors.add(:nav_key, :invalid, message: 'must exist in the default navigation tree') unless exists
    rescue StandardError
      # 导航未初始化（如纯数据脚本）时跳过校验
      nil
    end
  end
end
