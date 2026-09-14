module PallasTrade
  class ShippingCategory < PallasTrade.base_class
    has_prefix_id :scat

    DIGITAL_NAME = 'Digital'
    DEFAULT_NAME = 'Default'

    # PALLAS-CUSTOM (2026-09-14, PRD-20260914-shipping-category-name-i18n-fallback):
    # 分类名是**数据**（落库为字面名称，并被商品/配送方式引用），不得由 I18n 输出驱动 ——
    # 缺词条时 `I18n.t` 返回 "Translation missing: …" 文案，历史上它被当成名称写进了
    # `pallastrade_shipping_categories.name`（后台显示为乱码名并派生重复分类）。
    TRANSLATION_MISSING_MARKER = 'translation missing:'

    include PallasTrade::UniqueName

    with_options inverse_of: :shipping_category do
      has_many :products
      has_many :shipping_method_categories
    end
    has_many :shipping_methods, through: :shipping_method_categories

    def self.digital
      find_by(name: DIGITAL_NAME)
    end

    def self.default_category
      find_by(name: DEFAULT_NAME)
    end

    # name 是否为历史遗留的「缺失翻译文案」而非真实名称
    def self.legacy_translation_name?(value)
      value.to_s.downcase.start_with?(TRANSLATION_MISSING_MARKER)
    end

    # 数据修复（幂等）：把 name 为缺失翻译文案的遗留分类并入规范分类（Default / Digital），
    # 先迁移商品与配送方式关联，再删除遗留行；已规范的环境为空操作。
    # @return [Array<Array(Integer, Integer)>] [legacy_id, canonical_id] 列表
    def self.repair_legacy_names!
      repaired = []
      where('LOWER(name) LIKE ?', "#{TRANSLATION_MISSING_MARKER}%").find_each do |legacy|
        canonical_name = legacy.name.to_s.downcase.include?('.digital') ? DIGITAL_NAME : DEFAULT_NAME
        canonical = find_or_create_by!(name: canonical_name)
        next if canonical.id == legacy.id

        PallasTrade::Product.where(shipping_category_id: legacy.id).update_all(shipping_category_id: canonical.id)
        PallasTrade::ShippingMethodCategory.where(shipping_category_id: legacy.id).find_each do |join|
          PallasTrade::ShippingMethodCategory.find_or_create_by!(
            shipping_method_id: join.shipping_method_id,
            shipping_category_id: canonical.id
          )
          join.destroy!
        end
        legacy.destroy!
        repaired << [legacy.id, canonical.id]
      end
      repaired
    end

    # Returns true if this shipping category includes a digital shipping method
    # @return [Boolean]
    def includes_digital_shipping_method?
      @includes_digital_shipping_method ||= shipping_methods.digital.exists?
    end
  end
end
