# frozen_string_literal: true

# Contact messages — complaints & feedback from storefront, plus inbound replies.
class CreatePallasTradeContactMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_contact_messages do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :kind, default: 'feedback', null: false # complaint / feedback / inquiry / reply
      t.string :name
      t.string :email, null: false
      t.string :subject
      t.text :body, null: false
      t.string :status, default: 'pending', null: false # pending / in_progress / resolved
      t.string :reference_email # inbound message id / original email id for replies
      t.timestamps
    end

    add_index :pallastrade_contact_messages, [:store_id, :status]
    add_index :pallastrade_contact_messages, [:store_id, :kind]
  end
end
