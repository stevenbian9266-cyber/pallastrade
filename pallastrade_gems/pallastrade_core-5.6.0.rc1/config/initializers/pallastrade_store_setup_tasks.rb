# Default Getting Started tasks shown on the admin dashboard.
# See PallasTrade::SetupTasks for how to add or remove tasks.
Rails.application.config.after_initialize do
  PallasTrade.store_setup_tasks.add :setup_payment_method,
    position: 10,
    done: ->(store) { store.payment_method_setup? }

  PallasTrade.store_setup_tasks.add :add_products,
    position: 20,
    done: ->(store) { store.products.any? }

  PallasTrade.store_setup_tasks.add :set_customer_support_email,
    position: 30,
    done: ->(store) { store.customer_support_email.present? }

  PallasTrade.store_setup_tasks.add :setup_taxes_collection,
    position: 40,
    done: ->(_store) { PallasTrade::TaxRate.any? }

  PallasTrade.store_setup_tasks.add :setup_storefront,
    position: 50,
    done: ->(store) { store.storefront_setup? }
end
