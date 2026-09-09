module PallasTrade
  # OrderCancellation —— durable 取消意图（REV-P6-4/8j；源 §34/§35）。
  #
  # §34：取消意图必须 durable；OrderCancellation 继续作为取消 intent owner。REV-P6-8j（§34 落地 +
  # REV-P6-0 DB audit）：增加显式生命周期 state ——
  #   requested          意图已落库（Orders::Cancel 事务内创建）
  #   applied            已应用（订单 canceled + durable Refund(requested) 已建，同事务原子；terminal）
  #   failed             标记失败（保留事件；Orders::Cancel 失败路径保持整体回滚不留行）
  #   recovery_required  Ops 标记：已 applied 的取消需下游恢复关注（如资金意图未落地/退款行缺失）
  #   manual_review      人工复核
  # §35：Order=canceled 与 Refund=processing 合法并存（本行只表达取消意图；退款行各自表达终态）。
  class OrderCancellation < PallasTrade.base_class
    has_prefix_id :cncl

    REASONS = %w[customer declined fraud inventory staff other expired].freeze
    STATES = %w[requested applied failed recovery_required manual_review].freeze

    attribute :restock_items, :boolean, default: false
    attribute :refund_payments, :boolean, default: false
    attribute :notify_customer, :boolean, default: false
    attribute :metadata, default: -> { {} }
    attribute :state, :string, default: 'requested'

    belongs_to :order, class_name: 'PallasTrade::Order', inverse_of: :cancellations
    belongs_to :canceled_by, polymorphic: true, optional: true

    validates :order, presence: true
    validates :reason, presence: true, inclusion: { in: REASONS }
    validates :refund_amount, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
    validates :state, inclusion: { in: STATES }

    scope :requested, -> { where(state: 'requested') }
    scope :applied, -> { where(state: 'applied') }
    scope :failed, -> { where(state: 'failed') }
    scope :recovery_required, -> { where(state: 'recovery_required') }
    scope :manual_review, -> { where(state: 'manual_review') }
    # 需要人工/恢复关注的意图（§34 recovery_required + §35 人工复核）
    scope :needs_attention, -> { where(state: %w[recovery_required manual_review]) }

    state_machine :state, initial: :requested do
      # 取消已应用（订单 canceled + durable 退款意图已建）——Orders::Cancel 同事务驱动
      event :apply do
        transition requested: :applied
      end

      # 标记失败（Ops/异常路径；Orders::Cancel 失败路径仍整体回滚不留行——本事件供显式裁决）
      event :fail do
        transition %i[requested applied recovery_required manual_review] => :failed
      end

      # Ops：已 applied 的取消需要下游恢复关注
      event :flag_recovery_required do
        transition applied: :recovery_required
      end

      # Ops：人工复核
      event :flag_manual_review do
        transition %i[applied recovery_required] => :manual_review
      end

      # Ops：人工裁决后重新标记为已应用（恢复完成）
      event :reapply do
        transition %i[recovery_required manual_review failed] => :applied
      end
    end

    # 是否处于需要人工/恢复关注的意图状态
    def recovery_attention?
      recovery_required? || manual_review?
    end
  end
end
