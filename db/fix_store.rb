shop = PallasTrade::Store.find_by(code: 'shop')
pallastrade = PallasTrade::Store.find_by(code: 'pallastrade')

if shop && pallastrade
  shop.update!(default: false)
  pallastrade.update!(default: true)
  puts "Updated defaults: Shop=#{shop.default?}, PallasTrade=#{pallastrade.default?}"

  # Preserve admin access when the default store changes. Role assignments are
  # scoped to a store, so admins from the former default store otherwise lose
  # access to the admin panel after this script switches the default.
  PallasTrade.admin_user_class.pallastrade_admin.distinct.find_each do |admin_user|
    admin_user.add_role(PallasTrade::Role::ADMIN_ROLE, pallastrade)
  end
  puts "Ensured admin roles for PallasTrade store"
  
  # Verify API key resolution
  store = PallasTrade.current_store_finder.new(url: 'localhost:3000').execute
  puts "Store for localhost:3000: #{store.name} (id=#{store.id})"
  
  key = store.api_keys.active.publishable.first
  if key
    puts "API Key: #{key.token}"
  else
    puts "No API key for this store!"
    # Create one
    new_key = store.api_keys.create!(name: 'Storefront', key_type: 'publishable')
    puts "Created new key: #{new_key.token}"
  end
end
