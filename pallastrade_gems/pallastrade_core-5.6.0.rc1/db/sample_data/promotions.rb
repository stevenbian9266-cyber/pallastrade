promotion = PallasTrade::Promotion.where(
  name: 'Free Shipping',
  code: 'FREESHIP'
).first_or_create! do |promo|
  promo.store = PallasTrade::Store.default
end

PallasTrade::Promotion::Actions::FreeShipping.where(promotion: promotion).first_or_create!
