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

      # Error codes the AI endpoints can hand back (availability gates, gateway,
      # capability layer) plus `<code>` values the controller raises itself.
      # Anything outside this list still renders — see `ErrorFallback`.
      AI_ASSIST_ERROR_CODES = %w[
        ai_disabled ai_capability_disabled ai_model_disabled ai_provider_disabled
        ai_budget_exceeded ai_credentials_missing ai_credentials_invalid
        ai_provider_unavailable ai_output_invalid ai_unavailable
      ].freeze

      # Attributes for an `ai-assist` container.
      #
      # ⚠️ The `data:` wrapper is not cosmetic. Stimulus only attaches through
      # `data-controller` and only reads `data-ai-assist-*-value`; emitting the
      # same names without the `data-` prefix (which is what these five views did
      # until 2026-09-18) produces inert attributes — the controller is never
      # constructed, so `data-action="click->ai-assist#generate"` never fires and
      # the buttons look broken.
      #
      # @param endpoint [String] the AI endpoint this container calls
      # @param labels [Hash] extra labels, keyed by the controller's lookup name
      # @param values [Hash] extra Stimulus values (`product_id:`, `kind:`, …)
      # @return [Hash] ready for `tag.attributes`
      def ai_assist_attributes(endpoint:, labels: {}, **values)
        {
          data: {
            controller: 'ai-assist',
            ai_assist_endpoint_value: endpoint,
            ai_assist_labels: ai_assist_labels(labels).to_json,
            **values.transform_keys { |key| :"ai_assist_#{key}_value" }
          }
        }
      end

      # The controller resolves wording with `label(name)` and falls back to
      # `ErrorFallback` when a code has no wording of its own — a blank status
      # reads as "nothing happened" and sends the merchant clicking again.
      #
      # Keys must match the controller's lookup names character for character,
      # including case and the colon (`Entry:product_edit_ai`, `Error:<code>`);
      # they ride along as one JSON attribute precisely because those names
      # cannot survive being encoded as attribute names.
      #
      # @param extra [Hash] view-specific labels; merged last, so it can override
      # @return [Hash]
      def ai_assist_labels(extra = {})
        fallback = I18n.t('pallastrade.admin.products.ai.errors.default',
                          default: 'The AI request could not be completed.')

        labels = {
          'Idle' => I18n.t('pallastrade.admin.products.ai.idle', default: ''),
          'Generating' => I18n.t('pallastrade.admin.products.ai.generating', default: '…'),
          'Review' => I18n.t('pallastrade.admin.products.ai.review_hint', default: fallback),
          'Accepted' => I18n.t('pallastrade.admin.products.ai.accepted', default: fallback),
          'ErrorFallback' => fallback
        }

        AI_ASSIST_ERROR_CODES.each do |code|
          labels["Error:#{code}"] =
            I18n.t("pallastrade.admin.products.ai.errors.#{code}", default: fallback)
        end

        labels.merge(extra)
      end

      # Catalog Health pages carry their own wording for the shared states and
      # the two codes only they raise.
      # @return [Hash]
      def catalog_health_ai_labels
        {
          'Idle' => '',
          'Accepted' => '',
          'Generating' => PallasTrade.t('admin.catalog_health.ai.generating'),
          'Review' => PallasTrade.t('admin.catalog_health.ai.summary_heading'),
          'Error:nothing_to_fix' => PallasTrade.t('admin.catalog_health.ai.errors.nothing_to_fix'),
          'Error:unknown_issue' => PallasTrade.t('admin.catalog_health.ai.errors.unknown_issue'),
          'Entry:product_edit_ai' => PallasTrade.t('admin.catalog_health.ai.entries.product_edit_ai'),
          'Entry:translations_drawer' => PallasTrade.t('admin.catalog_health.ai.entries.translations_drawer'),
          'Entry:product_media' => PallasTrade.t('admin.catalog_health.ai.entries.product_media'),
          'Entry:variant_inventory' => PallasTrade.t('admin.catalog_health.ai.entries.variant_inventory'),
          'Entry:redirects' => PallasTrade.t('admin.catalog_health.ai.entries.redirects'),
          'Entry:publishing' => PallasTrade.t('admin.catalog_health.ai.entries.publishing')
        }
      end
    end
  end
end
