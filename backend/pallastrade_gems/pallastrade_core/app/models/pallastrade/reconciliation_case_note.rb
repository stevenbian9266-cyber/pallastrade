# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases；业务方案 §70.1）——
# 案例备注（留痕）：每次「加备注」新增一行，不覆盖历史。
module PallasTrade
  class ReconciliationCaseNote < PallasTrade.base_class
    belongs_to :reconciliation_case, class_name: 'PallasTrade::ReconciliationCase',
                                     inverse_of: :notes
    belongs_to :author, class_name: PallasTrade.admin_user_class.to_s, optional: true

    validates :body, presence: true, length: { maximum: 5000 }

    scope :chronological, -> { order(:created_at, :id) }
  end
end
