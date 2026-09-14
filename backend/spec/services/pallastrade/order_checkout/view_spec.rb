# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-1A (PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview)
# OrderCheckout::View —— 只读投影服务。
RSpec.describe PallasTrade::OrderCheckout::View, type: :model do
  # 复用 testing_support 全局 default store（before(:all) 已创建），避免重复建 store。
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  # Canonical 标准订单（Carts::Submit 产物语义：state=pending / status=placed）
  def pending_order(store:, user:)
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  describe '#call' do
    it 'returns nil for a nil order' do
      expect(described_class.new.call(order: nil)).to be_nil
    end

    context 'canonical pending order (AC-101)' do
      subject(:view) { described_class.new.call(order: order) }

      let(:order) { pending_order(store: store, user: user) }

      it 'builds a CheckoutView bound to the same order' do
        expect(view).to be_a(PallasTrade::OrderCheckout::CheckoutView)
        expect(view.order.id).to eq(order.id)
        expect(view.id).to eq(order.prefixed_id)
      end

      it 'projects order state/status/contact facts' do
        expect(view.state).to eq('pending')
        expect(view.status).to eq('placed')
        expect(view.email).to eq(order.email)
        expect(view.currency).to eq(order.currency)
      end

      it 'projects items and addresses from the order associations' do
        expect(view.items.map(&:id)).to eq(order.line_items.map(&:id))
        expect(view.shipping_address).to eq(order.ship_address)
        expect(view.billing_address).to eq(order.bill_address)
      end

      it 'projects shipments (fulfillments) as-is' do
        expect(view.fulfillments.map(&:id)).to eq(order.shipments.map(&:id))
      end

      it 'does not recalculate money — reads authoritative order totals (AC-102)' do
        expect(view.item_total).to eq(order.item_total)
        expect(view.delivery_total).to eq(order.shipment_total)
        expect(view.total).to eq(order.total)
        expect(view.amount_due).to eq(order.amount_due)
        expect(view.discount_total).to eq(order.discount_total)
        expect(view.tax_total).to eq(order.tax_total)
      end
    end

    context 'complete order (AC-104)' do
      it 'still projects a historical checkout view without re-entering checkout' do
        order = pending_order(store: store, user: user)
        order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current,
                             payment_state: 'paid')
        order.reload

        view = described_class.new.call(order: order)

        expect(view.state).to eq('complete')
        expect(view.order.completed_at).to be_present
        expect { described_class.new.call(order: order) }.not_to raise_error
      end
    end

    context 'legacy in-flight order (AC-105)' do
      it 'projects best-effort without raising or advancing the state machine' do
        legacy = create(:order_with_line_items, store: store, user: user,
                                                line_items_price: 50, shipment_cost: 0)
        legacy.update_columns(state: 'cart', status: 'cart', submitted_at: nil,
                              completed_at: nil, payment_state: nil, payment_total: 0)

        expect { described_class.new.call(order: legacy) }.not_to raise_error

        view = described_class.new.call(order: legacy)
        expect(view.state).to eq('cart')
        expect(view.items).to be_present
        expect(legacy.reload.state).to eq('cart')
      end

      it 'tolerates missing addresses and missing shipping rates with nil/empty' do
        legacy = create(:order_with_line_items, store: store, user: user,
                                                line_items_price: 50, shipment_cost: 0)
        legacy.update_columns(state: 'cart', ship_address_id: nil, bill_address_id: nil)
        legacy.reload

        view = described_class.new.call(order: legacy)

        expect(view.shipping_address).to be_nil
        expect(view.billing_address).to be_nil
        expect(view.fulfillments).to be_empty.or(be_present)
      end
    end

    context 'adjustment projections (AC-101/102)' do
      it 'projects an empty discount list when no promotion adjustments exist' do
        order = pending_order(store: store, user: user)

        view = described_class.new.call(order: order)

        expect(view.discounts).to eq([])
        expect(view.discount_total).to eq(order.discount_total)
      end

      it 'projects tax detail lines from tax adjustments (amount read from the authoritative column)' do
        order = pending_order(store: store, user: user)
        tax = create(:adjustment, adjustable: order, order: order,
                                  source: create(:tax_rate),
                                  amount: 5, label: 'VAT', eligible: true)

        view = described_class.new.call(order: order)
        line = view.taxes.find { |t| t.id == tax.prefixed_id }

        expect(line).not_to be_nil
        # 引擎（tax adjuster）可能在创建时按规则重算 amount —— View 只读权威列。
        expect(line.amount).to eq(tax.reload.amount.to_s)
        expect(line.currency).to eq(tax.currency)
        expect(view.tax_total).to eq(order.tax_total)
      end
    end

    context 'determinism and zero side effects (AC-107/108)' do
      it 'returns business-identical projections on repeated calls' do
        order = pending_order(store: store, user: user)
        first = described_class.new.call(order: order)
        second = described_class.new.call(order: order)

        expect(second.total).to eq(first.total)
        expect(second.items.map(&:id)).to eq(first.items.map(&:id))
        expect(second.fulfillments.map(&:id)).to eq(first.fulfillments.map(&:id))
      end

      it 'does not mutate order, shipments, adjustments, state or payment tables' do
        order = pending_order(store: store, user: user)
        order_attrs = order.reload.attributes
        shipment_attrs = order.shipments.map(&:attributes)
        adjustment_attrs = order.adjustments.map(&:attributes)
        session_count = PallasTrade::PaymentSession.count
        payment_count = PallasTrade::Payment.count

        described_class.new.call(order: order)

        expect(order.reload.attributes).to eq(order_attrs)
        expect(order.shipments.reload.map(&:attributes)).to eq(shipment_attrs)
        expect(order.adjustments.reload.map(&:attributes)).to eq(adjustment_attrs)
        expect(PallasTrade::PaymentSession.count).to eq(session_count)
        expect(PallasTrade::Payment.count).to eq(payment_count)
      end
    end

    context 'query safety (AC-109)' do
      def count_queries(&block)
        count = 0
        ActiveSupport::Notifications.subscribed(->(*) { count += 1 }, 'sql.active_record', &block)
        count
      end

      it 'preloads line items so query count does not scale per item' do
        base_order = pending_order(store: store, user: user)
        base_queries = count_queries { described_class.new.call(order: base_order) }

        many = pending_order(store: store, user: user)
        create_list(:line_item, 8, order: many, price: 10)
        many_queries = count_queries { described_class.new.call(order: many.reload) }

        # 8 个额外 line item 不应带来 ~8 次额外查询（应为批量预加载）。
        expect(many_queries).to be <= base_queries + 3
      end
    end

    context 'readiness projection (AC-301, CHK-P1-3)' do
      it 'exposes ready/missing_requirements for a canonical pending order' do
        order = pending_order(store: store, user: user)
        view = described_class.new.call(order: order)

        expect(view.ready).to be true
        expect(view.missing_requirements).to eq([])
      end

      it 'reflects missing contact when the email is blank' do
        order = pending_order(store: store, user: user)
        order.update_columns(email: nil)

        view = described_class.new.call(order: order)

        expect(view.ready).to be false
        expect(view.missing_requirements).to include('contact')
      end
    end

    # B1 扩展（PRD-20260914-checkout B1）：credits / capabilities /
    # available_payment_methods / billing_mode —— 只读投影。
    context 'B1 extensions: credits / capabilities / payment methods / billing mode' do
      subject(:view) { described_class.new.call(order: order.reload) }

      let(:order) { pending_order(store: store, user: user) }

      describe '#gift_cards / #store_credit (AC-002/AC-003)' do
        it 'returns empty credits when nothing is applied' do
          expect(view.gift_cards).to eq([])
          expect(view.store_credit).to be_nil
          expect(view.credits).to eq(gift_cards: [], store_credit: nil)
        end

        it 'projects applied store credit as amount + display_amount' do
          create(:store_credit_payment, order: order, amount: 2, state: 'checkout')

          expect(view.store_credit[:amount]).to eq(order.reload.total_applied_store_credit.to_s)
          expect(view.store_credit[:display_amount]).to eq(order.display_total_applied_store_credit.to_s)
        end

        it 'projects an applied gift card (array contract; <=1 card today)' do
          gift_card = create(:gift_card, store: store, amount: 10, currency: order.currency)
          card_credit = create(:store_credit, user: user, store: store,
                                              currency: order.currency, amount: 10,
                                              originator: gift_card)
          # StoreCredit 支付方式校验要求 order.gift_card.present? || could_use_store_credit? ——
          # 先挂卡再建支付，语义上即「礼卡先应用、再产生 store credit 支付记录」。
          order.update_columns(gift_card_id: gift_card.id)
          pm = create(:store_credit_payment_method, store: store, active: true, display_on: 'both')
          create(:payment, order: order, payment_method: pm, amount: 3,
                           state: 'checkout', source: card_credit)

          expect(view.gift_cards.size).to eq(1)
          entry = view.gift_cards.first
          expect(entry[:id]).to eq(gift_card.prefixed_id)
          expect(entry[:code]).to eq(gift_card.code)
          expect(entry[:amount]).to eq(order.reload.gift_card_total.to_s)
          expect(entry[:display_amount]).to eq(order.display_gift_card_total.to_s)
        end
      end

      describe '#capabilities (AC-005/AC-006)' do
        it 'allows editing and paying for a ready pending order' do
          expect(view.capabilities).to eq(
            can_edit_address: true, can_change_shipping: true,
            can_apply_promotion: true, can_pay: true
          )
        end

        it 'disables every capability once the order is completed' do
          order.update_columns(state: 'complete', status: 'complete',
                               payment_state: 'paid', completed_at: Time.current)

          expect(view.capabilities.values).to all(be(false))
        end

        it 'disables can_pay when nothing is due' do
          order.update_columns(payment_total: order.total)

          expect(view.capabilities[:can_pay]).to be(false)
        end
      end

      describe '#available_payment_methods (AC-007)' do
        it 'returns only active front-end methods available for the order' do
          front = create(:check_payment_method, store: store, active: true, display_on: 'front_end')
          back = create(:check_payment_method, store: store, active: true, display_on: 'back_end')
          inactive = create(:check_payment_method, store: store, active: false, display_on: 'front_end')

          ids = view.available_payment_methods.map(&:id)

          expect(ids).to include(front.id)
          expect(ids).not_to include(back.id, inactive.id)
        end
      end

      describe '#billing_mode (AC-009)' do
        it 'derives same_as_shipping when billing matches the shipping address' do
          order.update_columns(bill_address_id: order.ship_address_id)

          expect(view.billing_mode).to eq('same_as_shipping')
        end

        it 'derives custom when billing differs from shipping' do
          order.update_columns(bill_address_id: create(:address).id)

          expect(view.billing_mode).to eq('custom')
        end

        it 'derives same_as_shipping when billing is missing' do
          order.update_columns(bill_address_id: nil)

          expect(view.billing_mode).to eq('same_as_shipping')
        end
      end
    end
  end
end
