# frozen_string_literal: true

# Catalog Health V1 (PRD-20260915-admin-catalog-health-v1, FR-006): the products
# list shows a "filtered by catalog health issue" banner through the existing
# `products_header_partials` injection point instead of overriding the gem view
# (decision tree: admin extensions before view copies).
Rails.application.config.after_initialize do
  partial = 'pallastrade/admin/catalog_health/products_filter_banner'
  partials = PallasTrade.admin.partials.products_header

  partials << partial unless partials.include?(partial)

  # Product history timeline (PRD-20260915-catalog-batch-d1-product-history):
  # rendered in the product form sidebar through the documented injection point.
  history_partial = 'pallastrade/admin/products/history'
  sidebar_partials = PallasTrade.admin.partials.product_form_sidebar

  sidebar_partials << history_partial unless sidebar_partials.include?(history_partial)

  # Catalog Health card (PRD-20260916-catalog-batch-e3-ai-fix-suggestion FR-004b):
  # the product's own health issues plus the AI fix suggestion entry, rendered in
  # the same sidebar injection point.
  health_partial = 'pallastrade/admin/catalog_health/product_card'
  sidebar_partials << health_partial unless sidebar_partials.include?(health_partial)

  # D15 切片1 (PRD-20260916-payments-d15-risk-lists FR-008): the order page shows the latest
  # risk assessment (decision + masked matches) through the documented body injection point
  # instead of overriding the gem view (decision tree: admin extensions before view copies).
  risk_partial = 'pallastrade/admin/risk_lists/order_assessment_card'
  order_body_partials = PallasTrade.admin.partials.order_page_body

  order_body_partials << risk_partial unless order_body_partials.include?(risk_partial)
end
