# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # 可解释健康分（PRD-20260917-catalog-health-score）。
    #
    # 工作台原本只有 7 类 issue 的**计数**；计数没有分母就不可决策，而分母有了
    # 之后，商家还想要一个「我今天该不该慌」的总分。这个类把 `Coverage` 的比率
    # 加权成一个 0–100 的分数 —— 但它只有在**商家能拿计算器复算**时才有价值，
    # 所以三件事是硬要求：
    #
    #   1. **只用可计算的维度**：分母为 0（新店 / 单语言 / 无 URL 变更）或计数器
    #      报错的维度**既不按 0 也不按 1 计入**。当成 0 会凭空抬高总分，当成 1
    #      会凭空压低 —— 两种都是编造一个数字给商家看。
    #   2. **权重是常量且页面可见**：让「72 分怎么来的」有一个能指着看的答案。
    #   3. **每个维度都带「为什么没计入」**：UI 照实说，而不是让商家自己猜。
    #
    # 只读：不算分不写库，不碰任何商品。
    class Score
      # 各维权重。**等权是有意的**：权重越复杂越难解释，而分数的全部价值在于
      # 商家能照页面上的数字复算一遍。要调就改这里，并同步
      # `admin.catalog_health.score.weighting` 的说明文案。
      WEIGHTS = Issues::KEYS.index_with(1.0).freeze

      # @!attribute [r] key
      #   @return [String] issue key
      # @!attribute [r] missing
      #   @return [Integer] 分子（原样来自 `Coverage`，页面直接展示）
      # @!attribute [r] total
      #   @return [Integer] 分母（同上）
      # @!attribute [r] coverage_ratio
      #   @return [Float, nil] 覆盖率
      # @!attribute [r] weight
      #   @return [Float] 该维权重
      # @!attribute [r] counted
      #   @return [Boolean] 是否计入了总分
      # @!attribute [r] excluded_reason
      #   @return [Symbol, nil] 未计入的原因（`:no_denominator` / `:count_failed`）
      Dimension = Struct.new(:key, :missing, :total, :coverage_ratio, :weight,
                             :counted, :excluded_reason, keyword_init: true) do
        def coverage_percentage
          coverage_ratio && (coverage_ratio * 100).round(1)
        end
      end

      # @!attribute [r] score
      #   @return [Float, nil] 0.0~1.0；没有任何可计算维度时为 nil（页面不显示数字）
      # @!attribute [r] dimensions
      #   @return [Array<Dimension>]
      # @!attribute [r] counted_count
      #   @return [Integer] 计入总分的维度数
      # @!attribute [r] dimension_count
      #   @return [Integer] 总维度数
      Result = Struct.new(:score, :dimensions, :counted_count, :dimension_count,
                          keyword_init: true) do
        def computable?
          !score.nil?
        end

        def out_of_100
          score && (score * 100).round
        end
      end

      def self.call(store)
        new(store).call
      end

      # @param store [PallasTrade::Store]
      def initialize(store)
        @store = store
      end

      attr_reader :store

      # @return [Result]
      def call
        counted = dimensions.select(&:counted)

        if counted.empty?
          return Result.new(score: nil, dimensions: dimensions,
                            counted_count: 0, dimension_count: dimensions.size)
        end

        total_weight = counted.sum(&:weight)

        Result.new(
          score: counted.sum { |dimension| dimension.weight * dimension.coverage_ratio } / total_weight,
          dimensions: dimensions,
          counted_count: counted.size,
          dimension_count: dimensions.size
        )
      end

      # @return [Array<Dimension>] 顺序与 `Issues::KEYS` 一致
      def dimensions
        @dimensions ||= Coverage.call(store).metrics.map { |metric| build_dimension(metric) }
      end

      private

      def build_dimension(metric)
        counted = metric.computable?

        Dimension.new(
          key: metric.key,
          missing: metric.missing,
          total: metric.total,
          coverage_ratio: metric.coverage_ratio,
          weight: WEIGHTS.fetch(metric.key, 1.0),
          counted: counted,
          excluded_reason: counted ? nil : exclusion_reason(metric)
        )
      end

      # 未计入的原因 —— 必须区分「没有分母」与「计数器坏了」：
      # 前者是门店还没有可衡量的对象（正常），后者是系统问题，处理方式完全不同。
      def exclusion_reason(metric)
        metric.failed ? :count_failed : :no_denominator
      end
    end
  end
end
