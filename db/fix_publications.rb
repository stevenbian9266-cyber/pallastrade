ch1 = PallasTrade::ProductPublication.where(channel_id: 1).count
ch2 = PallasTrade::ProductPublication.where(channel_id: 2).count
puts "Before: ch1=#{ch1}, ch2=#{ch2}"

# Delete channel 1 publications (since channel 2 already has the valid ones)
deleted = PallasTrade::ProductPublication.where(channel_id: 1).delete_all
puts "Deleted #{deleted} publications from channel 1"

ch1 = PallasTrade::ProductPublication.where(channel_id: 1).count
ch2 = PallasTrade::ProductPublication.where(channel_id: 2).count
puts "After: ch1=#{ch1}, ch2=#{ch2}"
puts "DONE"
