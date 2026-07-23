# Ensure that PallasTrade.user_class includes the UserApiMethods concern

PallasTrade::Core::Engine.config.to_prepare do
  if PallasTrade.user_class && !PallasTrade.user_class.included_modules.include?(PallasTrade::UserApiMethods)
    PallasTrade.user_class.include PallasTrade::UserApiMethods
  end
end
