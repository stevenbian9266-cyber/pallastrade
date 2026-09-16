# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# 下单锁汇快照：**逐单可追溯的汇率凭证**。
#
#   * `display_rate`   —— 锁定当刻的展示汇率（来自 `CurrencyRate`，未含加点）；
#   * `up_charge_percent` / `effective_rate` —— 加点（markup）与加点后实际汇率（展示「含货币转换费」的读模型）；
#   * 结算侧字段（`settlement_rate` / `settlement_source` / `variance_bips` / `variance_status`）由 `Fx::Compare` 回填。
#
# 铁律：快照只**记录**汇率事实，不改订单/支付金额、不写资金流水。
module PallasTrade
  class FxSnapshot < PallasTrade.base_class
    VARIANCE_STATUSES = %w[pending matched mismatch undetermined].freeze
    SETTLEMENT_SOURCES = %w[provider_reported implied].freeze
    LOCKED_ON = %w[order.submitted manual].freeze

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true
    belongs_to :order, class_name: 'PallasTrade::Order', optional: true
    belongs_to :payment, class_name: 'PallasTrade::Payment', optional: true
    belongs_to :currency_rate, class_name: 'PallasTrade::CurrencyRate', optional: true

    validates :base_currency, :quote_currency, :display_rate, :effective_rate, :locked_at, presence: true
    validates :variance_status, inclusion: { in: VARIANCE_STATUSES }
    validates :locked_on, inclusion: { in: LOCKED_ON }
    validates :settlement_source, inclusion: { in: SETTLEMENT_SOURCES }, allow_nil: true
    validates :display_rate, :effective_rate, numericality: { greater_than: 0 }
    validates :up_charge_percent, numericality: { greater_than_or_equal_to: 0 }
    validates :order_id, uniqueness: { scope: %i[base_currency quote_currency] }

    scope :recent_first, -> { order(locked_at: :desc, id: :desc) }
    scope :for_store, ->(store) { where(store_id: store&.id) }
    scope :mismatched, -> { where(variance_status: 'mismatch') }
    scope :matched, -> { where(variance_status: 'matched') }
    # 待比对：尚未与结算汇率对齐（pending = 等结算；undetermined = 汇率来源不可判定）
    scope :awaiting_comparison, -> { where(variance_status: %w[pending undetermined]) }
    scope :locked_between, lambda { |from, to|
      where('pallastrade_fx_snapshots.locked_at >= ? AND pallastrade_fx_snapshots.locked_at < ?', from, to)
    }

    # 后台筛选（唯一口径：列表与计数共用）
    scope :filter_by, lambda { |store: nil, variance_status: nil, base_currency: nil, quote_currency: nil|
      result = store.present? ? for_store(store) : all
      result = result.where(variance_status: variance_status) if variance_status.present?
      result = result.where(base_currency: base_currency.to_s.upcase) if base_currency.present?
      result = result.where(quote_currency: quote_currency.to_s.upcase) if quote_currency.present?
      result
    }

    def mismatched?
      variance_status == 'mismatch'
    end

    def compared?
      compared_at.present?
    end

    # 偏差率（百分比，便于页面展示；bips 是权威口径）
    def variance_percent
      return nil if variance_bips.nil?

      (variance_bips.to_d / 100).round(4)
    end

    def signal_list
      Array(signals['list']).compact
    end

    def add_signal!(code)
      list = (signal_list + [code.to_s]).uniq
      update_columns(signals: (signals || {}).merge('list' => list))
    end
  end
end
