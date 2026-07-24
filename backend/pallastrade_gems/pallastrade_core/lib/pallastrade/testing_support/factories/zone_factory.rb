FactoryBot.define do
  factory :zone, class: PallasTrade::Zone do
    name        { generate(:random_string) }
    description { generate(:random_string) }

    factory :zone_with_country do
      kind { :country }

      zone_members do |proxy|
        zone = proxy.instance_eval { @instance }

        [PallasTrade::ZoneMember.create(zoneable: create(:country), zone: zone)]
      end

      factory :global_zone, class: PallasTrade::Zone do
        name { 'GlobalZone' }

        after(:create) do |zone|
          country_ids = PallasTrade::Country.pluck(:id)
          existing_ids = zone.zone_members.where(zoneable_type: 'PallasTrade::Country').pluck(:zoneable_id)
          new_ids = country_ids - existing_ids

          if new_ids.any?
            records = new_ids.map { |id| { zoneable_type: 'PallasTrade::Country', zoneable_id: id, zone_id: zone.id, created_at: Time.current, updated_at: Time.current } }
            PallasTrade::ZoneMember.insert_all(records)
          end
        end
      end
    end
  end
end
