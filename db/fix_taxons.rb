t3 = PallasTrade::Taxon.where(store_id: 3).count
tn = PallasTrade::Taxon.where(store_id: nil).count
PallasTrade::Taxon.where(store_id: 3).update_all(store_id: 4)
PallasTrade::Taxon.where(store_id: nil).update_all(store_id: 4)
t4 = PallasTrade::Taxon.where(store_id: 4).count
puts "Fixed from 3: #{t3}, from nil: #{tn}"
puts "Taxons at store 4: #{t4}"
puts "DONE"
