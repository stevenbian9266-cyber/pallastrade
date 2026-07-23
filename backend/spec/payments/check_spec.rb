# frozen_string_literal: true

require "spec_helper"

RSpec.describe PallasTrade::PaymentMethod::Check, type: :model do
  let(:store) { @default_store }
  let(:check_method) { create(:check_payment_method, store: store) }
  let(:product) { create(:product_in_stock, store: store) }
  let(:order) { create(:completed_order_with_totals, store: store, variants: [product.default_variant]) }

  def build_payment
    create(
      :payment,
      order: order,
      payment_method: check_method,
      source: nil,
      amount: order.total,
      state: "checkout"
    )
  end

  it "completes an auto-captured offline payment and records a capture event" do
    check_method.update!(auto_capture: true)
    payment = build_payment

    expect(payment.process!).to be_truthy

    payment.reload
    expect(payment).to be_completed
    expect(payment.capture_events.sum(:amount)).to eq(order.total)
    expect(payment.log_entries).to exist
  end

  it "leaves a manually captured offline payment pending after authorization" do
    check_method.update!(auto_capture: false)
    payment = build_payment

    expect(payment.process!).to be_truthy
    expect(payment.reload).to be_pending
    expect(payment.log_entries).to exist
  end

  it "cancels a completed offline payment through the payment state machine" do
    check_method.update!(auto_capture: true)
    payment = build_payment
    payment.process!

    expect(payment.cancel!).to be_truthy
    expect(payment.reload).to be_void
    expect(payment.state_changes.where(previous_state: "completed", next_state: "void")).to exist
  end

  it "only allows capture and void in valid payment states" do
    payment = build_payment

    expect(check_method.can_capture?(payment)).to be(true)
    expect(check_method.can_void?(payment)).to be(true)

    payment.update!(state: "void")
    expect(check_method.can_capture?(payment)).to be(false)
    expect(check_method.can_void?(payment)).to be(false)
  end

  it "treats a repeated capture of a completed payment as a no-op" do
    check_method.update!(auto_capture: true)
    payment = build_payment
    payment.process!
    capture_count = payment.capture_events.count

    expect(payment.capture!).to be(true)
    expect(payment.reload.capture_events.count).to eq(capture_count)
  end

  it "records the exact order total as the payable amount" do
    expect(build_payment.amount).to eq(order.total)
  end

  it "requires no source and returns successful gateway responses" do
    expect(check_method.source_required?).to be(false)
    expect(check_method.actions).to contain_exactly("capture", "void")
    expect(check_method.authorize(1_000)).to be_success
    expect(check_method.capture(1_000)).to be_success
    expect(check_method.credit(1_000)).to be_success
    expect(check_method.void("offline-reference")).to be_success
  end
end
