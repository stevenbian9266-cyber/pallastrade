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
      Metric = Struct.new(:key, :missing, :total, :missing_ratio, :coverage_ratio, keyword_init: true) do
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

      # @return [Array<Metric>] 两个指标，顺序固定
      def metrics
        @metrics ||= [seo, translations]
      end

      # @param key [String, Symbol]
      # @return [Metric, nil]
      def metric_for(key)
        metrics.find { |metric| metric.key == key.to_s }
      end

      # @return [Boolean] 两个指标都无法计算（新店 / 未配置语言）
      def empty?
        metrics.none?(&:computable?)
      end

      # @return [Metric] SEO 缺失率 —— 分母 = 未归档商品数
      def seo
        build(SEO_KEY, Issues.count(store, SEO_KEY), not_archived_products)
      end

      # @return [Metric] 翻译缺失率 —— 分母 = 商品数 × 支持语言数（与分子同单位）
      def translations
        build(TRANSLATION_KEY, Issues.count(store, TRANSLATION_KEY), Issues.translation_slots(store))
      end

      private

      def build(key, missing, total)
        missing = missing.to_i
        total = total.to_i

        return Metric.new(key: key, missing: missing, total: total, missing_ratio: nil, coverage_ratio: nil) if total.zero?

        ratio = missing.to_f / total

        Metric.new(key: key, missing: missing, total: total,
                   missing_ratio: ratio, coverage_ratio: 1.0 - ratio)
      end

      # 与 `Issues` 的 scope 同源：7 类 issue 一律不看已归档商品。
      def not_archived_products
        store.products.not_archived.count
      end
    end
  end
end
