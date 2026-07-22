# Clean PallasTrade Commerce Demo branding from product SEO metadata
count = 0
PallasTrade::Product.find_each do |p|
  changed = false
  if p.meta_title.present? && p.meta_title.include?('PallasTrade Commerce Demo')
    p.meta_title = p.meta_title.gsub(' | PallasTrade Commerce Demo', '')
    changed = true
  end
  if p.meta_description.present? && p.meta_description.include?('PallasTrade Commerce')
    p.meta_description = p.meta_description
      .gsub(' on the PallasTrade Commerce demo store.', ' on the PallasTrade store.')
      .gsub('PallasTrade Commerce demo store', 'PallasTrade store')
      .gsub('PallasTrade ecommerce in action.', 'PallasTrade ecommerce platform.')
    changed = true
  end
  if changed
    p.save!
    count += 1
  end
end
puts "Fixed #{count} products"

# Also check taxons
tcount = 0
PallasTrade::Taxon.find_each do |t|
  next unless t.meta_title.present? && t.meta_title.include?('PallasTrade Commerce Demo')
  t.meta_title = t.meta_title.gsub(' | PallasTrade Commerce Demo', '')
  t.save!
  tcount += 1
end
puts "Fixed #{tcount} taxons"
