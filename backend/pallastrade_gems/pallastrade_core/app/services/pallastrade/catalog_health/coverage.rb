# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # 商品健康的**覆盖率**指标（PRD-20260917-catalog-health-coverage-ratios；补方案 §十六）：
    #
    #   * `missing_seo`        —— 缺失 SEO 的商品占比
    #   * `missing_translations` —— 翻译缺口占「商品 × 语言」总槽位的比例
    #
    # 为什么需要它：工作台给的是**计数**，而计数没有分母就不可决策 ——
    # 「23 个商品缺 SEO」在只有 25 个商品的店里是灾难，在 5000 个的店里是噪声。
    #
    # 三条铁律：
    #   1. **分子只能来自 `Issues.count`** —— 那是判定口径的唯一权威（"计数 == 下钻列表条数"
    #      这条不变量靠它维持）。在这里另写判定 SQL 会让页面自相矛盾；
    #   2. **两个比率不共用分母** —— SEO 是按**商品**计数（分母 = 未归档商品数），
    #      翻译是按 **(商品 × 语言) 对数**计数（分母 = 商品数 × 支持语言数）。
    #      共用一个分母会算出一个错的比率，而且错得很像对的（D1）；
    #   3. **分母为 0 时比率为 `nil`，不编造** —— 新店没有商品时，显示 0% 会让人以为
    #      "已经做完了"，显示 100% 会让人以为"全坏了"。同理，"门店没有其它语言"
    #      ≠ "翻译完成 100%"（D3/D4）。
    #
    # 只读：不写任何表。
    class Coverage
      # @!attribute [r] key
      #   @return [String] issue key（`Issues::KEYS` 成员）
      # @!attribute [r] missing
      #   @return [Integer] 分子（与 `Issues.count` 严格相等）
      # @!attribute [r] total
      #   @return [Integer] 分母（0 表示无法计算）
      # @!attribute [r] missing_ratio
      #   @return [Float, nil] 缺失率（0.0~1.0），分母为 0 时为 nil
      # @!attribute [r] coverage_ratio
      #   @return [Float, nil] 覆盖率（1 - 缺失率），分母为 0 时为 nil
      # @!attribute [r] failed
      #   @return [Boolean] 计数器本身报错（区别于「真的是 0」），仅供 UI 说明原因
      Metric = Struct.new(:key, :missing, :total, :missing_ratio, :coverage_ratio, :failed,
                          keyword_init: true) do
        def computable?
          !missing_ratio.nil?
        end

        def missing_percentage
          missing_ratio && (missing_ratio * 100).round(1)
        end

        def coverage_percentage
          coverage_ratio && (coverage_ratio * 100).round(1)
        end
      end

      SEO_KEY = 'missing_seo'
      TRANSLATION_KEY = 'missing_translations'

      # 每一类 issue 的**分母**（单位必须与分子同源）。
      #
      # 为什么不能共用一个分母：7 类 issue 数的是**不同的东西** ——
      # 内容三类数商品、库存类数**在售**商品、草稿类数**草稿**商品、
      # 翻译数「商品 × 语言」槽位、URL 变更数变更条目。
      # 拿商品总数当所有类的分母会算出一个**很像对的**错比率
      # （铁律 2 已经为两类指标踩过这个坑，这里只是把它推到全部 7 类）。
      #
      # 为什么都带 `not_archived`：`Issues` 的 7 类一律不看已归档商品，分母必须同源。
      DENOMINATORS = {
        'missing_media' => :not_archived_products,
        'missing_description' => :not_archived_products,
        'missing_seo' => :not_archived_products,
        'missing_translations' => :translation_slots,
        'active_zero_stock' => :active_products,
        'old_drafts' => :draft_products,
        'redirect_unresolved' => :url_changes
      }.freeze

      def self.call(store)
        new(store).call
      end

      # @param store [PallasTrade::Store]
      def initialize(store)
        @store = store
      end

      attr_reader :store

      # @return [Coverage] self，便于链式调用
      def call
        self
      end

      # @return [Array<Metric>] 全部 7 类 issue 各一个指标，顺序与 `Issues::KEYS` 一致
      def metrics
        @metrics ||= Issues::KEYS.map { |key| build_metric(key) }
      end

      # @param key [String, Symbol]
      # @return [Metric, nil]
      def metric_for(key)
        metrics.find { |metric| metric.key == key.to_s }
      end

      # @return [Boolean] 全部指标都无法计算（新店 / 未配置语言 / 无 URL 变更）
      def empty?
        metrics.none?(&:computable?)
      end

      # @return [Metric] SEO 缺失率 —— 分母 = 未归档商品数
      def seo
        metric_for(SEO_KEY)
      end

      # @return [Metric] 翻译缺失率 —— 分母 = 商品数 × 支持语言数（与分子同单位）
      def translations
        metric_for(TRANSLATION_KEY)
      end

      private

      def build_metric(key)
        build(key, Issues.count(store, key), denominator_for(key))
      rescue StandardError => e
        # 单个计数器坏掉不能让整页垮掉（与 `Report#safe_count` 同一约定），
        # 但**绝不能当作 0**：0 会被健康分读成「这一类全好」，凭空抬高总分。
        # 用 `failed` 把它与「真的是 0」区分开，由 UI 如实说明原因。
        Rails.logger.warn("[catalog_health] coverage #{key} failed: #{e.class}: #{e.message}")

        Metric.new(key: key, missing: 0, total: 0,
                   missing_ratio: nil, coverage_ratio: nil, failed: true)
      end

      def denominator_for(key)
        # 白名单取自常量，不接受外部传入的方法名。
        send(DENOMINATORS.fetch(key.to_s, :zero_denominator))
      end

      def build(key, missing, total)
        missing = missing.to_i
        total = total.to_i

        return Metric.new(key: key, missing: missing, total: total,
                          missing_ratio: nil, coverage_ratio: nil, failed: false) if total.zero?

        ratio = missing.to_f / total

        Metric.new(key: key, missing: missing, total: total,
                   missing_ratio: ratio, coverage_ratio: 1.0 - ratio, failed: false)
      end

      def zero_denominator
        0
      end

      # 与 `Issues` 的 scope 同源：7 类 issue 一律不看已归档商品。
      def not_archived_products
        store.products.not_archived.count
      end

      # 库存类 issue（`active_zero_stock`）看的是**在售**商品 ——
      # 用商品总数当分母会把缺失率算小，而且小得很像对的。
      def active_products
        store.products.not_archived.where(status: 'active').count
      end

      # 草稿类 issue（`old_drafts`）看的是**草稿池** —— 分母是全部草稿，不是全部商品。
      def draft_products
        store.products.not_archived.where(status: 'draft').count
      end

      # 翻译分子数的是「（商品 × 语言）对数」，分母必须同单位。
      def translation_slots
        Issues.translation_slots(store)
      end

      # URL 变更分子数的是变更条目，分母同理；与 `redirect_unresolved` 的
      # 分母同源（`Issues.redirect_unresolved_count` 也走这个集合）。
      def url_changes
        PallasTrade::ProductUrlChange.call(store).count
      end
    end
  end
end
