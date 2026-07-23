# This migration comes from pallastrade (originally 20250207084000)
class AddAcceptsEmailMarketingFieldToPallasTradeUsersTable < ActiveRecord::Migration[6.1]
  def change
    add_column PallasTrade.user_class.table_name, :accepts_email_marketing, :boolean, default: false, null: false, if_not_exists: true
    add_index PallasTrade.user_class.table_name, :accepts_email_marketing, if_not_exists: true
  end
end
