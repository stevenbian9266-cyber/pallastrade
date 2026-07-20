class CreateSpreeReports < ActiveRecord::Migration[6.1]
  def change
    create_table :pallastrade_reports do |t|
      t.references :store, null: false
      t.references :user
      t.string 'type'
      t.string 'currency'
      t.datetime 'date_from'
      t.datetime 'date_to'
      t.timestamps
    end
  end
end
