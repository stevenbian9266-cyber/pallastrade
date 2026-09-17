module PallasTrade
  class Policy < PallasTrade.base_class
    has_prefix_id :pol

    extend FriendlyId
    include PallasTrade::TranslatableResource

    UNIQUENESS_SCOPE = %i[owner_id owner_type].freeze

    #
    # FriendlyId
    #
    friendly_id :slug_candidates, use: %i[slugged scoped history], scope: UNIQUENESS_SCOPE

    #
    # Associations
    #
    belongs_to :owner, polymorphic: true, touch: true # can be a store or a vendor or organization

    #
    # Translations
    #
    TRANSLATABLE_FIELDS = %i[name body].freeze
    RICH_TEXT_TRANSLATABLE_FIELDS = %i[body].freeze
    translates(*TRANSLATABLE_FIELDS, column_fallback: PallasTrade.mobility_column_fallback)

    #
    # ActionText
    #
    translates :body, backend: :action_text

    #
    # 结构化退货条款（PRD-20260917-catalog-json-ld-phase2 FR-005）
    #
    # 数据源：商品页结构化数据的 `hasMerchantReturnPolicy`（schema.org `MerchantReturnPolicy`）。
    # 存成 preference 而不是列，理由见迁移 `20260917090000_add_preferences_to_pallastrade_policies`：
    # Policy 是四类政策共用的通用模型，开退货专用列会污染另外三类，且枚举无法演进。
    #
    # 为什么挂在**政策记录**上而不是门店上：后台已经有一个 Policies 编辑页
    # （商家本就在那里写退货政策正文），前台也已经按 slug 取政策
    # （Store API `policies#show` + 商店前台 `client.policies.get`）——
    # 条款与它描述的正文同处一页、同一次请求，不需要新端点、新菜单、新下发通道。
    serialize :preferences, type: Hash, coder: YAML, default: {}

    # 退货政策类目。'' = 未设置（此时整条政策不输出，见 `#merchant_return_policy_terms`）。
    RETURN_POLICY_CATEGORIES = %w[not_permitted finite_window unlimited_window].freeze

    # 退货方式 / 费用承担方。'' = 未设置（不输出该属性，而不是输出一个默认值）。
    RETURN_POLICY_METHODS = %w[by_mail in_store].freeze
    RETURN_POLICY_FEES = %w[free customer_pays].freeze

    preference :merchant_return_policy_category, :string, default: ''
    preference :merchant_return_policy_days, :integer, nullable: true, default: nil
    preference :merchant_return_policy_method, :string, default: ''
    preference :merchant_return_policy_fees, :string, default: ''
    # ISO-2 国家码，逗号分隔。空 = 留空，由调用方回退到门店默认国家。
    preference :merchant_return_policy_countries, :string, default: ''

    # 自由文本 → 白名单枚举。认不出就当**没填**（返回 nil），不猜也不回退默认值。
    # @param value [String, nil]
    # @param allowed [Array<String>]
    # @return [String, nil]
    def self.normalize_return_policy_enum(value, allowed)
      normalized = value.to_s.strip.downcase
      allowed.include?(normalized) ? normalized : nil
    end

    # 结构化退货条款的**归一化读模型**，供 API 序列化层使用。
    #
    # 归一化的意义：后台输入是自由文本，脏值（拼错的枚举、0 或负数的天数）必须在这里
    # 收敛掉 —— 否则会把一条「有限窗口但没说多少天」的**残缺政策**喂给搜索引擎，
    # 那比不输出更糟（会被判为结构化数据错误）。
    #
    # **不满足门槛就返回 nil**，由调用方整体省略该字段。
    #
    # @return [Hash, nil] `{ category:, days:, method:, fees:, countries: }`
    def merchant_return_policy_terms
      category = self.class.normalize_return_policy_enum(
        preferred_merchant_return_policy_category, RETURN_POLICY_CATEGORIES
      )
      return nil if category.nil?

      days = preferred_merchant_return_policy_days.to_i

      if category == 'finite_window'
        # 有限窗口必须给出正天数 —— 这是 schema.org 的硬要求。
        return nil unless days.positive?
      else
        # 不支持退货 / 无限期带天数是自相矛盾的，归一为「无天数」而不是原样输出。
        days = nil
      end

      {
        category: category,
        days: days,
        method: self.class.normalize_return_policy_enum(
          preferred_merchant_return_policy_method, RETURN_POLICY_METHODS
        ),
        fees: self.class.normalize_return_policy_enum(
          preferred_merchant_return_policy_fees, RETURN_POLICY_FEES
        ),
        countries: preferred_merchant_return_policy_countries.to_s
                                                              .split(',')
                                                              .map { |code| code.strip.upcase }
                                                              .reject(&:blank?)
                                                              .uniq
      }
    end

    # 这条政策是不是店铺的「退货政策」？
    #
    # 为什么要比较**名称**而不是 slug：slug 由 friendly_id 从（可翻译的）名称生成，
    # 非英文门店会得到完全不同的 slug；而名称是 `Store#create_default_policies`
    # 建政策时写进去的那个翻译键 —— 比较它才与「这条政策是怎么被建出来的」同源。
    #
    # ⚠️ 为什么是「任何语言对得上就算」，而不是在门店默认语言下比一次：
    # 建政策时 `name` 会被写进**当时 `I18n.locale` 那一条翻译行**，与门店的
    # `default_locale` 无关（列上往往还是空的）。实测：在 zh-CN 界面下建的店，
    # 退货政策的名字存在 zh-CN 翻译行里、`name` 列为 nil —— 此时若只在 `default_locale`
    # 下读，会得到 nil 并判定 false，商家就**看不到**该填的结构化条款字段。
    # 所以这里把「政策名（列值 + 每条翻译）」与「各语言的退货政策文案」做交叉比对，
    # 任意一边对得上即成立。
    #
    # 用途：后台表单用它决定要不要渲染「结构化退货条款」分组，
    # 序列化器用它挡住「值被写到别的政策上」的情况
    # （PRD-20260917-catalog-json-ld-phase2 FR-005/FR-007）。
    #
    # @return [Boolean]
    def returns_policy?
      actual_names.any? do |name|
        expected_names.any? { |expected| name.casecmp?(expected) }
      end
    end

    private

    # 这条政策在各处留下的名字：列上的原值 + 每一条翻译。
    # @return [Array<String>]
    def actual_names
      ([read_attribute(:name)] + translations.map(&:name))
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
    end

    # 「退货政策」在各语言下的文案 —— 与 `Store#create_default_policies` 用的是同一批键。
    # @return [Array<String>]
    def expected_names
      locales = ([:en] + Array(owner.try(:supported_locales_list)) +
                 translations.map { |translation| translation.locale.to_sym })
                .compact.uniq

      locales.filter_map do |locale|
        I18n.t('pallastrade.returns_policy', locale: locale, default: nil)
            .to_s.strip.presence
      end
    end

    public

    #
    # Validations
    #
    validates :slug, presence: true, uniqueness: { scope: UNIQUENESS_SCOPE }
    validates :name, presence: true
    validates :owner, presence: true

    #
    # Scopes
    #
    scope :with_body, -> { joins(:rich_text_body).distinct }
    scope :without_body, -> { where.missing(:rich_text_body) }
    scope :with_matching_name, ->(name_to_match) do
      value = name_to_match.to_s.strip.downcase

      if PallasTrade.use_translations?
        i18n { name.lower.eq(value) }
      else
        where(arel_table[:name].lower.eq(value))
      end
    end

    #
    #  Ransack
    #
    self.whitelisted_ransackable_attributes = %w[name owner_type owner_id]

    before_destroy :really_destroy_slugs!

    # For policies, store.policies returns all policies owned by the store
    # We don't want to filter out other policies in requests that use `for_store` when they have a different owner type
    def self.for_store(store)
      store.policies.or(where.not(owner_type: 'PallasTrade::Store'))
    end

    def with_body?
      body.present?
    end

    def really_destroy_slugs!
      slugs.with_deleted.each(&:really_destroy!)
    end
  end
end
