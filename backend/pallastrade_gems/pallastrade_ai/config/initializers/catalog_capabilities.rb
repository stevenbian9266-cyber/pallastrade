# frozen_string_literal: true

# Product copy capabilities (PRD-20260915-catalog-batch-e1-ai-copilot FR-001).
#
# Registered in every environment (unlike `test_capabilities.rb`, which is
# dev/test only): the merchant-facing assistants on the product edit page need
# them in production. Registration stays inert until a store configures the AI
# provider, the capability setting and credentials — the Gateway's availability
# gates decide that per request.
Rails.application.reloader.to_prepare do
  next if PallasTrade::AI.capabilities.registered?('catalog.product_description')

  PallasTrade::AI.capabilities.register(
    'catalog.product_description',
    handler: 'PallasTrade::AI::Schemas::Catalog::ProductDescription::Handler',
    input_schema: 'PallasTrade::AI::Schemas::Catalog::ProductDescription::Input',
    output_schema: 'PallasTrade::AI::Schemas::Catalog::ProductDescription::Output',
    authorization: { action: :update, subject: 'PallasTrade::Product' },
    execution: :sync,
    allowed_parameters: %i[temperature max_output_tokens],
    required_model_capabilities: %i[text],
    display_name: 'Product description',
    description: 'Drafts or rewrites a product description for the admin to review before saving.',
    data_classification: 'internal',
    version: '1.0.0'
  )

  PallasTrade::AI.capabilities.register(
    'catalog.product_seo',
    handler: 'PallasTrade::AI::Schemas::Catalog::ProductSeo::Handler',
    input_schema: 'PallasTrade::AI::Schemas::Catalog::ProductSeo::Input',
    output_schema: 'PallasTrade::AI::Schemas::Catalog::ProductSeo::Output',
    authorization: { action: :update, subject: 'PallasTrade::Product' },
    execution: :sync,
    allowed_parameters: %i[temperature max_output_tokens],
    required_model_capabilities: %i[text],
    display_name: 'Product SEO',
    description: 'Suggests a meta title and meta description for the admin to review before saving.',
    data_classification: 'internal',
    version: '1.0.0'
  )

  # Batch E-2 — AI Translate Missing（PRD-20260915-catalog-batch-e2-ai-translate-missing FR-001）。
  next if PallasTrade::AI.capabilities.registered?('catalog.product_translation')

  PallasTrade::AI.capabilities.register(
    'catalog.product_translation',
    handler: 'PallasTrade::AI::Schemas::Catalog::ProductTranslation::Handler',
    input_schema: 'PallasTrade::AI::Schemas::Catalog::ProductTranslation::Input',
    output_schema: 'PallasTrade::AI::Schemas::Catalog::ProductTranslation::Output',
    authorization: { action: :update, subject: 'PallasTrade::Product' },
    execution: :sync,
    allowed_parameters: %i[temperature max_output_tokens],
    required_model_capabilities: %i[text],
    display_name: 'Product translation',
    description: 'Translates the product fields that are still missing in a locale, for the admin to review before saving.',
    data_classification: 'internal',
    version: '1.0.0'
  )
end
