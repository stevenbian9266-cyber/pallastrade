module PallasTrade
  class PromotionCategory < PallasTrade.base_class
    has_prefix_id :procat

    validates :name, presence: true
    has_many :promotions

    # PALLAS-CUSTOM: PRD-20260911-promo-batch6 —— 后台分类表格（Promotions → Categories）
    # 支持按名称/编码搜索排序；默认白名单仅含 name。
    self.whitelisted_ransackable_attributes = %w[name code]
  end
end
