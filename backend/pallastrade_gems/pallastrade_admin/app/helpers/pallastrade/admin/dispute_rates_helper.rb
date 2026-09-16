# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board）——
# 拒付率看板的展示辅助。**脱敏口径不另立一套**：卡指纹复用 D15 名单模块的 `masked_value`
# （`abcd***3456` 形制），保证「同一份卡指纹在名单页与看板页脱敏结果一致」。
module PallasTrade
  module Admin
    module DisputeRatesHelper
      UNKNOWN_BUCKET = 'unknown'

      # 视图辅助：卡指纹脱敏
      def mask_fingerprint(raw)
        PallasTrade::Admin::DisputeRatesHelper.masked(raw)
      end

      # 非视图上下文（控制器 / 服务）复用的同一实现
      # @param raw [String, nil]
      # @return [String]
      def self.masked(raw)
        value = raw.to_s.strip
        return UNKNOWN_BUCKET if value.blank?

        PallasTrade::PaymentRiskList.new(
          list_type: 'denylist', subject_type: 'card_fingerprint', value: value
        ).masked_value
      end
    end
  end
end
