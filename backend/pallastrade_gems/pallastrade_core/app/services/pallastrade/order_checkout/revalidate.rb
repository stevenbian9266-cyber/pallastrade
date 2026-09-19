# frozen_string_literal: true

# PALLAS-CUSTOM: PRD-20260919-checkout-结算页待支付订单再次支付重验（失效行剔除/优惠复核/金额变化提示）
#
# OrderCheckout::Revalidate —— 补付（再次支付）前的「商业事实重验」唯一编排：
#   ① 失效行判定（与购物车剔行共用 Catalog::LineItemAvailability）
#   ②（写）剔除失效行 + 行级释放库存预留
#   ③ 报价窗口失效/缺失 → 按当前目录/价目表重定价（窗口内 = 锁价）
#   ④ 优惠复核：不再满足 → Promotions::RemoveApplication（复用核销释放 + 调整行清理）
#   ⑤ 抵扣再平衡：礼品卡 / 店铺余额按新应付重新套用（复用既有 Apply 服务）
#   ⑥ OrderCheckout::Refresh（重算 + price_version/checkout_version 自增 + 报价窗口续期）
#   ⑦ 结构化报告（blockers / changes / invalid_items / quote / before-after 金额）
#
# 零副作用契约：`dry_run: true`（默认）—— 订单支付页预检不得改单、不得发事件、不得建会话。
# 实现：在 `order.with_lock` 事务内跑完整写路径，结束时 `ActiveRecord::Rollback` 回滚；
# 事务外可观察的副作用（inventory.released / order.items_removed 事件）只在写路径执行。
# 同一实现同时服务 `GET payment_preflight`（dry_run）与 `Transactions::Start`（写路径），
# 保证「页面显示金额 == 实际扣款金额」。
module PallasTrade
  module OrderCheckout
    class Revalidate
      prepend PallasTrade::ServiceModule::Base

      # 就绪度中「真正阻断补付」的三项；balance 另由 payable? 判定
      BLOCKING_READINESS = %w[contact shipping_address delivery_rate].freeze

      # 金额快照字段（raw 判逻辑 / display 渲染 —— 与 money 契约一致）
      MONEY_FIELDS = %w[item_total delivery_total tax_total discount_total total amount_due].freeze

      # @param order [PallasTrade::Order]
      # @param dry_run [Boolean] true = 只读预检（事务内执行后回滚）
      # @return [PallasTrade::ServiceModule::Result] success(report)
      def call(order:, dry_run: true)
        return failure(nil, 'Order not found') if order.nil?

        @dry_run = dry_run
        report = nil

        order.with_lock do
          order.reload
          # dry-run 期间关闭事件发布（`PallasTrade::Events.disable` 是线程级临时开关）：
          # 行删除/重算会经由 shipment/inventory 重建触发 `inventory.*` 等事件，
          # 而事件是**事务回滚无法撤销**的副作用 —— 页面预检必须一个都不发。
          report = @dry_run ? PallasTrade::Events.disable { reconcile(order) } : reconcile(order)
          raise ActiveRecord::Rollback if @dry_run
        end

        success(report)
      end

      private

      def reconcile(order)
        before = money_snapshot(order)
        window = quote_window_state(order)

        # 无行项目的订单（退化/异常/历史测试数据）没有可重验的商业事实：
        # 不跑重定价/重算（按行项目重算会把这类订单的金额归零），交下游门禁处理。
        return empty_report(order, before, window) if order.line_items.empty?

        credits = credit_intent(order)
        invalid = detect_invalid_items(order)
        changes = []

        blockers = terminal_blockers(order)
        # 就绪度阻断只在「确实经过标准收银台（曾签发报价窗口）」的订单上强制：
        # 无窗口的历史/异常订单保留旧行为（不因地址缺失而新堵死），
        # 但仍会做商品/金额/优惠/抵扣/配送可达性重验。
        blockers += readiness_blockers(order) if order.checkout_expires_at.present?

        if blockers.empty?
          changes.concat(prune_invalid_items!(order, invalid))
          order = order.reload
          delivery = delivery_blocker(order)
          blockers << delivery if delivery.present?
        end

        if blockers.empty?
          changes.concat(reprice_items!(order)) unless window['valid']
          changes.concat(remove_ineligible_promotions!(order))
          order = order.reload
          changes.concat(rebalance_credits!(order, credits))

          # 只有「窗口失效/缺失」或「确实改了什么」才 Refresh（重算 + 版本自增 + 续窗）；
          # 无变化时保持版本稳定，避免每次点 Pay 都无谓地推进 checkout_version。
          if !window['valid'] || changes.any?
            refresh = PallasTrade::OrderCheckout::Refresh.call(order: order)
            if refresh.success?
              order = order.reload
              @window_reissued = true
            else
              blockers << blocked('refresh_failed', refresh.error.to_s.presence || 'Quote refresh failed')
            end
          end
        end

        after = money_snapshot(order)
        changes.concat(money_changes(before, after))

        build_report(order, before, after, window, invalid, blockers, changes)
      end

      # --- ① 判定 ------------------------------------------------------------

      def detect_invalid_items(order)
        order.line_items.includes(variant: :product).filter_map do |line_item|
          reason = PallasTrade::Catalog::LineItemAvailability.unavailable_reason(line_item)
          next if reason.nil?

          { line_item: line_item, reason: reason }
        end
      end

      def terminal_blockers(order)
        return [] unless order.canceled? || order.completed?

        [blocked('order_not_payable', 'Order is not payable in its current state')]
      end

      def readiness_blockers(order)
        readiness = PallasTrade::OrderCheckout::Readiness.call(order: order)
        missing = readiness.missing_requirements & BLOCKING_READINESS
        return [] if missing.empty?

        [blocked('checkout_not_ready',
                 "Checkout is not ready: missing #{missing.join(', ')}",
                 'missing_requirements' => missing)]
      end

      # 目的地可达性：剔除失效行之后再判（只读谓词，零副作用）
      def delivery_blocker(order)
        return nil if order.line_items.empty? || order.shipments.empty?
        return nil unless order.requires_ship_address?

        unreachable = order.line_items_without_shipping_rates
        return nil if unreachable.empty?

        blocked('delivery_unavailable',
                'Some items cannot be shipped to the current destination',
                'items' => unreachable.map { |line_item| item_payload(line_item) })
      end

      # --- ② 剔除失效行 -------------------------------------------------------

      def prune_invalid_items!(order, invalid)
        return [] if invalid.empty?

        changes = invalid.map { |entry| change('item_removed', 'item_removed', item_payload(entry[:line_item]).merge('reason' => entry[:reason])) }

        invalid.each do |entry|
          line_item = entry[:line_item]

          # 释放该行库存预留（写路径才释放：inventory.released 是事务外可观察的副作用）
          unless @dry_run
            PallasTrade::StockReservations::Release.call(
              order: order, line_item: line_item, reason: 'line_item_unavailable'
            )
          end

          # 订单行删除的既有权威（后台订单编辑同款）；内部会重算订单
          PallasTrade::LineItems::Destroy.call(line_item: line_item)

          unless @dry_run
            order.publish_event('order.items_removed',
                                payload: { order_id: order.prefixed_id,
                                           line_item_id: line_item.prefixed_id,
                                           variant_id: line_item.variant&.prefixed_id,
                                           reason: entry[:reason] })
          end
        end

        changes
      end

      # --- ③ 重定价（仅窗口失效/缺失） -----------------------------------------

      def reprice_items!(order)
        items = order.line_items.includes(:variant).to_a
        return [] if items.empty?

        before = items.index_with { |line_item| line_item.price.to_s }
        order.update_line_item_prices!

        items.filter_map do |line_item|
          price_before = before[line_item]
          line_item.reload
          next if price_before == line_item.price.to_s

          change('price_changed', 'line_item',
                 'line_item_id' => line_item.prefixed_id,
                 'variant_id' => line_item.variant&.prefixed_id,
                 'name' => line_item.name,
                 'before' => price_before,
                 'after' => line_item.price.to_s)
        end
      end

      # --- ④ 优惠复核 ---------------------------------------------------------

      def remove_ineligible_promotions!(order)
        order.promotions.reload.to_a.filter_map do |promotion|
          next if promotion.eligible?(order)

          name = promotion.name
          code = promotion.code
          PallasTrade::Promotions::RemoveApplication.call(
            order: order, promotion: promotion, reason: 'promotion_ineligible'
          )

          change('promotion_removed', 'promotion',
                 'name' => name,
                 'code' => code,
                 'promotion_id' => promotion_id_for(promotion))
        end.tap do
          order.reload
        end
      end

      # --- ⑤ 抵扣再平衡 -------------------------------------------------------

      # 剔除商品会触发 CartLegacy::Recalculate（内含 remove_gift_card + 清 store-credit checkout 支付），
      # 因此必须显式按新应付重新套用，否则抵扣被静默吞掉（或反向多扣）。
      def rebalance_credits!(order, credits)
        changes = []

        if credits['gift_card_id'].present? && order.gift_card.blank?
          gift_card = PallasTrade::GiftCard.find_by(id: credits['gift_card_id'])
          if gift_card
            result = order.apply_gift_card(gift_card)
            changes << change('credit_adjusted', 'gift_card',
                              'gift_card_id' => gift_card.prefixed_id,
                              'before' => credits['gift_card_amount'],
                              'after' => order.reload.gift_card_total.to_s) if result.respond_to?(:success?) && result.success?
          end
        end

        if credits['store_credit_amount'].to_d.positive?
          order.reload
          PallasTrade.checkout_add_store_credit_service.call(order: order, amount: credits['store_credit_amount'].to_d)
          changes << change('credit_adjusted', 'store_credit',
                            'before' => credits['store_credit_amount'],
                            'after' => store_credit_applied(order.reload).to_s)
        end

        changes
      end

      # 剔除前的抵扣意图（剔除后支付行会被清理，必须提前取）
      def credit_intent(order)
        gift_card = order.gift_card
        gift_card_applied =
          if gift_card.present?
            order.payments.store_credits.checkout.where(source: gift_card.store_credits).sum(:amount)
          else
            0.to_d
          end

        {
          'gift_card_id' => gift_card&.id,
          'gift_card_amount' => gift_card_applied.to_s,
          'store_credit_amount' => (store_credit_applied(order) - gift_card_applied).to_s
        }
      end

      # --- ⑦ 报告 -------------------------------------------------------------

      def build_report(order, before, after, window, invalid, blockers, changes)        if blockers.empty? && !payable?(order)
          blockers = [if order.line_items.reload.empty?
                        blocked('no_payable_items', 'No payable items remain on this order')
                      else
                        blocked('no_payable_amount', 'Order has no payable amount')
                      end]
        end

        {
          'payable' => blockers.empty?,
          'order_id' => order.prefixed_id,
          'number' => order.number,
          'blockers' => blockers,
          'changes' => changes,
          'invalid_items' => invalid.map do |entry|
            item_payload(entry[:line_item]).merge('reason' => entry[:reason])
          end,
          'quote' => quote_payload(order),
          'amount_due_before' => before['amount_due'],
          'amount_due_after' => after['amount_due'],
          'display_amount_due_before' => before['display_amount_due'],
          'display_amount_due_after' => after['display_amount_due'],
          'total_before' => before['total'],
          'total_after' => after['total'],
          'display_total_before' => before['display_total'],
          'display_total_after' => after['display_total'],
          'window' => window.merge('reissued' => !!@window_reissued)
        }
      end

      # 无行项目订单的退化报告（不重验、不改单）：仅陈述当前事实与窗口状态。
      def empty_report(order, before, window)
        {
          'payable' => payable?(order),
          'order_id' => order.prefixed_id,
          'number' => order.number,
          'blockers' => [],
          'changes' => [],
          'invalid_items' => [],
          'quote' => quote_payload(order),
          'amount_due_before' => before['amount_due'],
          'amount_due_after' => before['amount_due'],
          'display_amount_due_before' => before['display_amount_due'],
          'display_amount_due_after' => before['display_amount_due'],
          'total_before' => before['total'],
          'total_after' => before['total'],
          'display_total_before' => before['display_total'],
          'display_total_after' => before['display_total'],
          'window' => window.merge('reissued' => false)
        }
      end

      def quote_payload(order)
        {
          'checkout_version' => order.checkout_version,
          'price_version' => order.price_version,
          'expires_at' => order.checkout_expires_at&.iso8601,
          'amount_due' => order.amount_due.to_s,
          'display_amount_due' => order.display_amount_due.to_s,
          'total' => order.total.to_s,
          'display_total' => order.display_total.to_s
        }
      end

      def money_changes(before, after)        MONEY_FIELDS.filter_map do |field|
          next if before[field] == after[field]

          change("#{field}_changed", 'money',
                 'field' => field,
                 'before' => before[field],
                 'after' => after[field],
                 'display_before' => before["display_#{field}"],
                 'display_after' => after["display_#{field}"])
        end
      end

      def money_snapshot(order)        snapshot = {
          'item_count' => order.item_count,
          'gift_card_total' => order.gift_card_total.to_s,
          'store_credit_applied' => store_credit_applied(order).to_s
        }

        MONEY_FIELDS.each do |field|
          snapshot[field] = order.public_send(field).to_s
          snapshot["display_#{field}"] = order.public_send("display_#{field}").to_s
        end

        snapshot
      end

      def quote_window_state(order)
        expires_at = order.checkout_expires_at

        {
          'valid' => expires_at.present? && expires_at.future?,
          'expires_at' => expires_at&.iso8601,
          'window_minutes' => PallasTrade::OrderCheckout::Policies.quote_window.to_i / 60
        }
      end

      def payable?(order)
        !order.canceled? && !order.completed? && order.amount_due.to_d.positive?
      end

      def store_credit_applied(order)
        order.payments.store_credits.checkout.sum(:amount)
      end

      def promotion_id_for(promotion)
        promotion.respond_to?(:prefixed_id) ? promotion.prefixed_id : promotion.id.to_s
      end

      def item_payload(line_item)
        {
          'line_item_id' => line_item.prefixed_id,
          'variant_id' => line_item.variant&.prefixed_id,
          'name' => line_item.name,
          'sku' => line_item.variant&.sku,
          'quantity' => line_item.quantity,
          'amount' => line_item.amount.to_s
        }
      end

      def change(kind, subject, payload)
        { 'kind' => kind, 'subject' => subject }.merge(payload.transform_keys(&:to_s))
      end

      def blocked(code, message, extra = {})
        { 'code' => code, 'message' => message }.merge(extra.transform_keys(&:to_s))
      end
    end
  end
end
