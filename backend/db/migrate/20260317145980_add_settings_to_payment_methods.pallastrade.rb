# This migration comes from pallastrade (originally 20211203082008)
class AddSettingsToPaymentMethods < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_payment_methods do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_payment_methods, :settings, :jsonb
      else
        add_column :pallastrade_payment_methods, :settings, :json
      end
    end
  end
end
