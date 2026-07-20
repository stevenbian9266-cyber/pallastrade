class CreateSpreePolicies < ActiveRecord::Migration[7.2]
  def change
    create_table :pallastrade_policies do |t|
      t.belongs_to :store, null: false
      t.string :slug, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :pallastrade_policies, [:store_id, :slug], unique: true
    create_table :pallastrade_policy_translations do |t|
      t.string :locale, null: false
      t.string :name
      t.references :PALLASTRADE_policy, null: false

      t.timestamps
    end

    add_index :pallastrade_policy_translations, [:PALLASTRADE_policy_id, :locale], unique: true
  end
end
