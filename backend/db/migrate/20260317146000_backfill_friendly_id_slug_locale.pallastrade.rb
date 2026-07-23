# This migration comes from pallastrade (originally 20230110142344)
class BackfillFriendlyIdSlugLocale < ActiveRecord::Migration[6.1]
  def up
    if PallasTrade::Store.default.present? && PallasTrade::Store.default.default_locale.present?
      FriendlyId::Slug.unscoped.update_all(locale: PallasTrade::Store.default.default_locale)
    end
  end

  def down
    FriendlyId::Slug.unscoped.update_all(locale: nil)
  end
end
