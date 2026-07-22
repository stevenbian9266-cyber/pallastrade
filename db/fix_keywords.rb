Rails.cache.clear

count = 0
PallasTrade::Product.find_each do |p|
  changed = false
  if p.meta_keywords.present?
    new_kw = p.meta_keywords
      .gsub(', pallastrade commerce demo', '')
      .gsub('pallastrade commerce demo, ', '')
      .gsub('pallastrade commerce demo', '')
    if new_kw != p.meta_keywords
      p.meta_keywords = new_kw
      changed = true
    end
  end
  if changed
    p.save!
    count += 1
  end
end
puts "Fixed #{count} product keywords"

# Verify
p = PallasTrade::Product.find_by(slug: 'semi-automatic-espresso-machine')
puts "meta_title: #{p.meta_title.inspect}"
puts "meta_description: #{p.meta_description.inspect}"
puts "meta_keywords: #{p.meta_keywords.inspect}"
