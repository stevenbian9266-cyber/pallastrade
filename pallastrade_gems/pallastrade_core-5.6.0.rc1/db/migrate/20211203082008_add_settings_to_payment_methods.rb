class AddSettingsToPaymentMethods < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_payment_methods do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_payment_methods, :settings, :jsonb
      else
        add_column :PALLASTRADE_payment_methods, :settings, :json
      end
    end
  end
end
