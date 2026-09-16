# frozen_string_literal: true

module PallasTrade
  module Admin
    # AI Product Copilot helper (PRD-20260915-catalog-batch-e1-ai-copilot
    # FR-006): tells the product form whether a capability can be used right now.
    #
    # The admin engine must stay usable without the AI engine installed, so every
    # access is guarded — a store without `pallastrade_ai` simply renders no
    # assistant, and a store with the engine but no configuration gets a disabled
    # button plus the reason code.
    # Note: Zeitwerk resolves this file to `AIAssistHelper` (the 'AI' acronym is
    # registered in `backend/config/initializers/inflections.rb`).
    module AIAssistHelper
      # @param capability [String] capability key
      # @return [Hash, nil] `{ available:, reason: }`, or nil when the AI engine is absent
      def ai_assist_state(capability)
        return nil unless defined?(PallasTrade::AI::AvailabilityService)

        check = PallasTrade::AI::AvailabilityService.check(
          capability: capability,
          store: current_store,
          actor: ai_assist_actor
        )

        { available: check[:available], reason: check[:reason] }
      end

      # @param state [Hash, nil]
      # @return [String, nil] tooltip / label for a disabled button
      #
      # ⚠️ 这个字符串会进入 **HTML 属性**（button 的 `title`），所以**不能**用 `PallasTrade.t`：
      # Rails 的 translate helper 在缺 key 时会返回
      # `<span class="translation_missing" title="translation missing: ...">默认值</span>`
      # —— 带标签的 HTML 插进属性会把属性撕开，残渣（如 `Default">`）泄漏成可见文本
      # （2026-09-16 实测：zh-CN 缺 admin.products.ai.disabled_reason.* 时，
      #  /admin/catalog_health 的 AI 按钮上出现了 `Default"> AI 修复建议`）。
      # `I18n.t` 返回纯字符串；配合带兜底的 default，这里永远不会渲染出 translation missing。
      def ai_assist_reason_label(state)
        return nil if state.nil? || state[:available]

        key = "pallastrade.admin.products.ai.disabled_reason.#{state[:reason]}"
        fallback = I18n.t(
          'pallastrade.admin.products.ai.disabled_reason.default',
          default: 'AI is not configured for this store yet.'
        )

        I18n.t(key, default: fallback).to_s.strip.presence
      end

      # @return [PallasTrade::AdminUser, nil]
      def ai_assist_actor
        klass = PallasTrade.admin_user_class
        return nil unless klass

        method_name = "current_#{klass.model_name.singular_route_key}"
        respond_to?(method_name) ? send(method_name) : nil
      end
    end
  end
end
