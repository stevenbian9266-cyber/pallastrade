# Deep clean all PallasTrade branding from product/taxon SEO and description text
count = { products: 0, taxons: 0 }

PallasTrade::Product.find_each do |p|
  changed = false

  # meta_title
  if p.meta_title.present?
    new_title = p.meta_title
      .gsub(' | PallasTrade Commerce Demo', '')
      .gsub('PallasTrade Commerce Demo', 'PallasTrade')
    if new_title != p.meta_title
      p.meta_title = new_title
      changed = true
    end
  end

  # meta_description
  if p.meta_description.present?
    new_desc = p.meta_description
      .gsub(' on the PallasTrade Commerce demo store.', ' on the PallasTrade store.')
      .gsub('PallasTrade Commerce demo store', 'PallasTrade store')
      .gsub('PallasTrade ecommerce in action.', '')
      .gsub('Powered by PallasTrade.', '')
      .gsub('Powered by PallasTrade', '')
      .gsub(/\s+\.$/, '.')
      .strip
    if new_desc != p.meta_description
      p.meta_description = new_desc
      changed = true
    end
  end

  # description (full text)
  if p.description.present? && p.description.include?('PallasTrade')
    new_full = p.description
      .gsub('PallasTrade Commerce', 'PallasTrade')
      .gsub(' pallastrade ', ' PallasTrade ')
      .gsub('PallasTrade demo', 'PallasTrade demo')
    if new_full != p.description
      p.description = new_full
      changed = true
    end
  end

  if changed
    p.save!
    count[:products] += 1
  end
end

PallasTrade::Taxon.find_each do |t|
  changed = false
  if t.meta_title.present? && t.meta_title.include?('PallasTrade Commerce Demo')
    t.meta_title = t.meta_title.gsub(' | PallasTrade Commerce Demo', '')
    changed = true
  end
  if t.meta_description.present? && t.meta_description.include?('PallasTrade')
    t.meta_description = t.meta_description.gsub('PallasTrade Commerce demo store', 'PallasTrade store')
    changed = true
  end
  if changed
    t.save!
    count[:taxons] += 1
  end
end

puts "Fixed #{count[:products]} products, #{count[:taxons]} taxons"
