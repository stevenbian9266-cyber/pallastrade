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
end
