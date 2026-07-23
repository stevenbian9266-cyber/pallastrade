Rails.application.config.after_initialize do
  # Register product_properties_enabled preference if not already defined
  unless PallasTrade::Config.respond_to?(:product_properties_enabled)
    PallasTrade::Core::Configuration.preference :product_properties_enabled, :boolean, default: false
  end

  # Register permitted attributes for product properties
  unless PallasTrade::PermittedAttributes::ATTRIBUTES.include?(:product_properties_attributes)
    PallasTrade::PermittedAttributes::ATTRIBUTES.push(:product_properties_attributes, :property_attributes)

    PallasTrade::PermittedAttributes.class_eval do
      mattr_accessor :product_properties_attributes
      mattr_accessor :property_attributes
    end

    PallasTrade::PermittedAttributes.product_properties_attributes = [
      :property_name, :property_id, :value, :position, :_destroy
    ]
    PallasTrade::PermittedAttributes.property_attributes = [
      :name, :presentation, :position, :kind, :display_on
    ]

    # Re-delegate the new attributes
    PallasTrade::Core::ControllerHelpers::StrongParameters.delegate(
      :product_properties_attributes,
      :property_attributes,
      to: :permitted_attributes,
      prefix: :permitted
    )
  end

  # Override permitted_product_attributes to include product_properties_attributes
  PallasTrade::Core::ControllerHelpers::StrongParameters.module_eval do
    def permitted_product_attributes
      permitted_attributes.product_attributes + [
        variants_attributes: permitted_variant_attributes + ['id', :_destroy],
        master_attributes: permitted_variant_attributes + ['id'],
        product_properties_attributes: permitted_product_properties_attributes + ['id', :_destroy]
      ]
    end
  end

  # Register product form partial for properties
  if defined?(PallasTrade::Admin) && Rails.application.config.respond_to?(:pallastrade_admin)
    Rails.application.config.pallastrade_admin.product_form_partials << 'pallastrade/admin/products/form/properties'
  end

  # Register admin navigation
  if defined?(PallasTrade::Admin) && PallasTrade.respond_to?(:admin)
    sidebar_nav = PallasTrade.admin.navigation.sidebar

    products_item = sidebar_nav.find(:products)
    if products_item
      builder = PallasTrade::Admin::Navigation::Builder.new(sidebar_nav, products_item)
      builder.add :properties,
                  label: :properties,
                  url: :admin_properties_path,
                  position: 50,
                  if: -> { can?(:manage, PallasTrade::Property) && PallasTrade::Config.product_properties_enabled }
    end
  end
end
