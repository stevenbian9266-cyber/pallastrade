# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        # TXN P2 收口 (PRD-20260905-other-txn-p2-closure-report-and-store-serializer):
        # Store CommerceTransaction serializer（只读格式化 + typelize source）。
        # 供 R1 契约基建（typelizer）生成 SDK 类型，以及后续 TXN-P2-6 controller
        # 从手写 payload 切换到本 serializer（输出与 P2-2 create 响应一致）。
        # 零副作用：不做计算/不推进状态机。
        class CommerceTransactionSerializer < PallasTrade::Api::V3::BaseSerializer
          typelize id: :string, state: :string, purpose: :string, currency: :string,
                   amount: :string,
                   checkout_version: [:number, { nullable: true }],
                   price_version: [:string, { nullable: true }],
                   snapshot_fingerprint: [:string, { nullable: true }],
                   completed_at: [:string, { nullable: true }],
                   started_at: [:string, { nullable: true }],
                   payment_confirmed_at: [:string, { nullable: true }],
                   finalizing_at: [:string, { nullable: true }],
                   recovery_required_at: [:string, { nullable: true }],
                   manual_review_at: [:string, { nullable: true }],
                   canceled_at: [:string, { nullable: true }],
                   recovery_attempts: :number,
                   last_error_class: [:string, { nullable: true }],
                   last_error_code: [:string, { nullable: true }],
                   last_error_message: [:string, { nullable: true }]

          attribute :id, &:prefixed_id
          attributes :state, :purpose, :currency

          attribute :amount do |tx|
            tx.amount.to_s
          end

          attribute :checkout_version, &:checkout_version
          attribute :price_version, &:price_version
          attribute :snapshot_fingerprint, &:snapshot_fingerprint
          attribute :recovery_attempts, &:recovery_attempts
          attribute :last_error_class, &:last_error_class
          attribute :last_error_code, &:last_error_code
          attribute :last_error_message, &:last_error_message

          %i[started_at payment_confirmed_at finalizing_at completed_at
             recovery_required_at manual_review_at canceled_at].each do |stamp|
            attribute stamp do |tx|
              tx.public_send(stamp)&.iso8601
            end
          end
        end
      end
    end
  end
end
