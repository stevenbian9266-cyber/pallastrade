# frozen_string_literal: true

module PallasTrade
  module Admin
    # REV-P6-8g：PaymentCombination 状态徽章（index/show 共用；BaseController 已注册 helper）。
    module PaymentCombinationsHelper
      # 状态 → badge 样式（与 refunds_ops badge 同色系；succeeded=绿 / pending|processing=蓝 /
      # failed|canceled|expired=红 / 灰兜底）
      COMBINATION_STATE_BADGE = {
        'pending' => 'badge-info',
        'processing' => 'badge-info',
        'succeeded' => 'badge-success',
        'failed' => 'badge-danger',
        'canceled' => 'badge-danger',
        'expired' => 'badge-danger'
      }.freeze

      def combination_state_badge(combination)
        state = combination.status.to_s
        css = COMBINATION_STATE_BADGE.fetch(state, 'badge-secondary')
        content_tag(:span, state, class: "badge #{css}")
      end

      def combination_currency(combination)
        combination.currency.to_s.upcase
      end

      def combination_amount_label(combination)
        "#{combination.amount} #{combination_currency(combination)}"
      end

      def split_amount_label(split, column)
        value = split.public_send(column)
        "#{format('%.2f', value.to_f)} #{split.currency.to_s.upcase}"
      end
    end
  end
end
