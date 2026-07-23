# This migration comes from pallastrade (originally 20260515000001)
class AddStoreIdToPallasTradeNewsletterSubscribers < ActiveRecord::Migration[7.2]
  def up
    add_reference :pallastrade_newsletter_subscribers, :store

    # For pallastrade_multi_tenant we need handle the backfill and indices there
    return if defined?(PallasTradeMultiTenant)

    default_store = PallasTrade::Store.default
    PallasTrade::NewsletterSubscriber.update_all(store_id: default_store.id) if default_store&.persisted?

    change_column_null :pallastrade_newsletter_subscribers, :store_id, false

    remove_index :pallastrade_newsletter_subscribers, :email, unique: true, if_exists: true
    add_index :pallastrade_newsletter_subscribers, [:email, :store_id], unique: true, if_not_exists: true
  end

  def down
    unless defined?(PallasTradeMultiTenant)
      remove_index :pallastrade_newsletter_subscribers, [:email, :store_id], if_exists: true
      add_index :pallastrade_newsletter_subscribers, :email, unique: true, if_not_exists: true
    end

    remove_reference :pallastrade_newsletter_subscribers, :store
  end
end
