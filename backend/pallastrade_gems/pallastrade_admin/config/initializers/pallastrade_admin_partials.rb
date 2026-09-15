# frozen_string_literal: true

# Catalog Health V1 (PRD-20260915-admin-catalog-health-v1, FR-006): the products
# list shows a "filtered by catalog health issue" banner through the existing
# `products_header_partials` injection point instead of overriding the gem view
# (decision tree: admin extensions before view copies).
Rails.application.config.after_initialize do
  partial = 'pallastrade/admin/catalog_health/products_filter_banner'
  partials = PallasTrade.admin.partials.products_header

  partials << partial unless partials.include?(partial)
end
