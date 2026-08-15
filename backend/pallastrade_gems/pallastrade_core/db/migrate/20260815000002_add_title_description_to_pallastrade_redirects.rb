# frozen_string_literal: true

# SEO 301 redirects — business-facing title/description so the admin list is
# readable ("what business is this redirect for") instead of raw paths only.
class AddTitleDescriptionToPallasTradeRedirects < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_redirects, :title, :string
    add_column :pallastrade_redirects, :description, :text
  end
end
