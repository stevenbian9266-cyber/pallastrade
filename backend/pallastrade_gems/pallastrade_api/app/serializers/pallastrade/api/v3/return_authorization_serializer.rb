# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      class ReturnAuthorizationSerializer < BaseSerializer
        typelize number: :string, status: :string,
                 order_id: [:string, nullable: true], stock_location_id: [:string, nullable: true],
                 return_authorization_reason_id: [:string, nullable: true],
                 # PALLAS-CUSTOM: 售后归属（PRD-20260824 FR-036）
                 order_parent_id: [:string, nullable: true],
                 order_is_child: :boolean,
                 order_children_ids: [:array, nullable: true]

        attributes :number

        attribute :status do |return_authorization|
          return_authorization.state.to_s
        end

        attribute :order_id do |return_authorization|
          return_authorization.order&.prefixed_id
        end

        # PALLAS-CUSTOM: 售后归属展示（FR-036）— 父订单 / 子订单
        attribute :order_parent_id do |return_authorization|
          return_authorization.order&.parent&.prefixed_id
        end

        attribute :order_is_child do |return_authorization|
          return_authorization.order&.child_order? ? true : false
        end

        attribute :order_children_ids do |return_authorization|
          return_authorization.order&.children&.map(&:prefixed_id) || []
        end

        attribute :stock_location_id do |return_authorization|
          return_authorization.stock_location&.prefixed_id
        end

        attribute :return_authorization_reason_id do |return_authorization|
          return_authorization.reason&.prefixed_id
        end
      end
    end
  end
end
