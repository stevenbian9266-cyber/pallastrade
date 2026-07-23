%w[warranty capacity voltage wattage runtime room_coverage noise_level connectivity].each do |key|
  PallasTrade::MetafieldDefinition.find_or_create_by!(
    namespace: 'custom',
    key: key,
    resource_type: 'PallasTrade::Product'
  )
end
