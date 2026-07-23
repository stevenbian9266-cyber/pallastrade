require_relative 'dependencies_helper'

module PallasTrade
  module Core
    class Dependencies
      INJECTION_POINTS_WITH_DEFAULTS = {
        # ability
        ability_class: 'PallasTrade::Ability',

        # cart
        cart_compare_line_items_service: 'PallasTrade::CompareLineItems',
        cart_create_service: 'PallasTrade::Cart::Create',
        cart_add_item_service: 'PallasTrade::Cart::AddItem',
        cart_update_service: 'PallasTrade::Cart::Update',
        cart_recalculate_service: 'PallasTrade::Cart::Recalculate',
        cart_remove_item_service: 'PallasTrade::Cart::RemoveItem',
        cart_remove_line_item_service: 'PallasTrade::Cart::RemoveLineItem',
        cart_set_item_quantity_service: 'PallasTrade::Cart::SetQuantity',
        cart_estimate_shipping_rates_service: 'PallasTrade::Cart::EstimateShippingRates',
        cart_empty_service: 'PallasTrade::Cart::Empty',
        cart_destroy_service: 'PallasTrade::Cart::Destroy',
        cart_associate_service: 'PallasTrade::Cart::Associate',
        cart_change_currency_service: 'PallasTrade::Cart::ChangeCurrency',
        cart_remove_out_of_stock_items_service: 'PallasTrade::Cart::RemoveOutOfStockItems',

        # carts
        carts_complete_service: 'PallasTrade::Carts::Complete',

        # checkout
        checkout_next_service: 'PallasTrade::Checkout::Next',
        checkout_advance_service: 'PallasTrade::Checkout::Advance',
        checkout_update_service: 'PallasTrade::Checkout::Update',
        checkout_complete_service: 'PallasTrade::Checkout::Complete',
        checkout_add_store_credit_service: 'PallasTrade::Checkout::AddStoreCredit',
        checkout_remove_store_credit_service: 'PallasTrade::Checkout::RemoveStoreCredit',
        checkout_get_shipping_rates_service: 'PallasTrade::Checkout::GetShippingRates',
        checkout_select_shipping_method_service: 'PallasTrade::Checkout::SelectShippingMethod',

        # gift cards
        gift_card_apply_service: 'PallasTrade::GiftCards::Apply',
        gift_card_remove_service: 'PallasTrade::GiftCards::Remove',
        gift_card_redeem_service: 'PallasTrade::GiftCards::Redeem',

        # order
        order_approve_service: 'PallasTrade::Orders::Approve',
        order_cancel_service: 'PallasTrade::Orders::Cancel',
        order_complete_service: 'PallasTrade::Orders::Complete',
        order_create_service: 'PallasTrade::Orders::Create',
        order_update_service: 'PallasTrade::Orders::Update',
        order_updater: 'PallasTrade::OrderUpdater',

        # fulfillment
        fulfillment_create_service: 'PallasTrade::Fulfillments::Create',

        # shipment
        shipment_change_state_service: 'PallasTrade::Shipments::ChangeState',
        shipment_create_service: 'PallasTrade::Shipments::Create',
        shipment_update_service: 'PallasTrade::Shipments::Update',
        shipment_add_item_service: 'PallasTrade::Shipments::AddItem',
        shipment_remove_item_service: 'PallasTrade::Shipments::RemoveItem',

        # tracking numbers
        tracking_number_service: 'PallasTrade::TrackingNumbers::BaseService',

        # sorter
        collection_sorter: 'PallasTrade::BaseSorter',
        order_sorter: 'PallasTrade::BaseSorter',
        posts_sorter: nil,
        products_sorter: 'PallasTrade::Products::Sort',
        # paginator
        collection_paginator: nil,

        # coupons
        # TODO: we should split this service into 2 separate - Add and Remove
        coupon_handler: 'PallasTrade::PromotionHandler::Coupon',

        # account
        account_create_service: 'PallasTrade::Account::Create',
        account_update_service: 'PallasTrade::Account::Update',

        # addresses
        address_create_service: 'PallasTrade::Addresses::Create',
        address_update_service: 'PallasTrade::Addresses::Update',

        # credit cards
        credit_cards_destroy_service: 'PallasTrade::CreditCards::Destroy',

        # classifications
        classification_reposition_service: nil,

        # line items
        line_item_create_service: 'PallasTrade::LineItems::Create',
        line_item_update_service: 'PallasTrade::LineItems::Update',
        line_item_destroy_service: 'PallasTrade::LineItems::Destroy',

        payment_create_service: 'PallasTrade::Payments::Create',
        payments_handle_webhook_service: 'PallasTrade::Payments::HandleWebhook',

        # finders
        address_finder: 'PallasTrade::Addresses::Find',
        country_finder: 'PallasTrade::Countries::Find',
        cms_page_finder: nil, # LEGACY
        menu_finder: nil, # LEGACY
        current_order_finder: 'PallasTrade::Orders::FindCurrent',
        current_store_finder: 'PallasTrade::Stores::FindDefault',
        completed_order_finder: 'PallasTrade::Orders::FindComplete',
        credit_card_finder: 'PallasTrade::CreditCards::Find',
        posts_finder: nil,
        products_finder: 'PallasTrade::Products::Find',
        taxon_finder: 'PallasTrade::Taxons::Find',
        line_item_by_variant_finder: 'PallasTrade::LineItems::FindByVariant',
        variant_finder: 'PallasTrade::Variants::Find',

        # search
        search_product_presenter: 'PallasTrade::SearchProvider::ProductPresenter'
      }.freeze

      include PallasTrade::DependenciesHelper
    end
  end
end
