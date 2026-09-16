# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # 把快照读成趋势（PRD-20260916-catalog-health-trend-snapshot FR-004）。
    #
    # 语义：
    #   * `current`  = 窗口内**最新**一条快照的计数；
    #   * `baseline` = 窗口内**最早可用**一条快照的计数；
    #   * `delta`    = current − baseline（负数 = 待办变少 = 治理有效）；
    #   * `direction`: `improving` / `worsening` / `flat` / **`unknown`**。
    #
    # 为什么必须有 `unknown`：新店、启用首日、或窗口内只有一条快照时，"变化"是**不存在的事实**。
    # 把它显示成「持平」是在编造结论 —— 商家会据此以为"这轮治理没效果"，而真相是"还没法判断"。
    #
    # 基准点取**窗口内最早可用快照**而不是"昨天"：与前一日比会把日内噪音放大成趋势。
    class Trend
      DEFAULT_DAYS = 30

      Row = Struct.new(:key, :current, :baseline, :delta, :direction, :points, keyword_init: true) do
        def improving? = direction == :improving
        def worsening? = direction == :worsening
        def flat? = direction == :flat
        def unknown? = direction == :unknown
      end

      # @param store [PallasTrade::Store]
      # @param days [Integer] 窗口天数（含当天）
      # @param on [Date] 窗口终点
      def self.call(store, days: DEFAULT_DAYS, on: Date.current)
        new(store, days: days, on: on).call
      end

      def initialize(store, days: DEFAULT_DAYS, on: Date.current)
        @store = store
        @days = normalize_days(days)
        @on = on
      end

      attr_reader :store, :days, :on

      # @return [Trend] self，便于链式调用
      def call
        self
      end

      # @return [Array<Row>] 每个 issue 一行，顺序与工作台一致
      def rows
        @rows ||= Issues::KEYS.map { |key| build_row(key) }
      end

      # @param key [String, Symbol]
      # @return [Row, nil]
      def row_for(key)
        rows.find { |row| row.key == key.to_s }
      end

      # @return [Integer, nil] 窗口内 net 变化（任一 issue 可判定时才有意义）
      def total_delta
        return nil if empty?

        rows.sum { |row| row.delta.to_i }
      end

      # @return [Boolean] 窗口内没有任何可比较的快照
      def empty?
        rows.all?(&:unknown?)
      end

      # @return [Date] 窗口起点（含）
      def since
        on - (days - 1)
      end

      private

      def normalize_days(value)
        days = value.to_i
        days.positive? ? days : DEFAULT_DAYS
      end

      # 一次查询取回窗口内的全部快照，再在内存分组 —— 查询数不随天数增长（NFR-004）。
      def snapshots_by_key
        @snapshots_by_key ||= PallasTrade::CatalogHealthSnapshot.
                              where(store_id: store.id).
                              where(captured_on: since..on).
                              order(:captured_on, :id).
                              group_by(&:issue_key)
      end

      def build_row(key)
        points = snapshots_by_key[key.to_s] || []

        # 少于两条快照 = 没有可比的两个时点 → unknown（不得编造持平）。
        return Row.new(key: key.to_s, current: nil, baseline: nil, delta: nil,
                       direction: :unknown, points: []) if points.size < 2

        baseline = points.first.count
        current = points.last.count
        delta = current - baseline

        Row.new(key: key.to_s, current: current, baseline: baseline, delta: delta,
                direction: direction_for(delta), points: points.map(&:count))
      end

      def direction_for(delta)
        return :flat if delta.zero?

        delta.negative? ? :improving : :worsening
      end
    end
  end
end
