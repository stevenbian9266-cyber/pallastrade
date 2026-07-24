module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.has_many :product_properties, dependent: :destroy, inverse_of: :product
      base.has_many :properties, through: :product_properties

      base.accepts_nested_attributes_for :product_properties, allow_destroy: true, reject_if: lambda { |pp|
        pp[:property_id].blank? || (pp[:id].blank? && pp[:value].blank?)
      }

      base.whitelisted_ransackable_associations |= %w[properties]

      # Property scopes
      base.add_search_scope :with_property do |property|
        joins(:properties).where(PallasTrade::Product.property_conditions(property))
      end

      base.add_search_scope :with_property_value do |property, value|
        if PallasTrade.use_translations?
          joins(:properties).
            join_translation_table(PallasTrade::Property).
            join_translation_table(PallasTrade::ProductProperty).
            where(PallasTrade::ProductProperty.translation_table_alias => { value: value }).
            where(PallasTrade::Product.property_conditions(property))
        else
          joins(:properties).
            where(PallasTrade::ProductProperty.table_name => { value: value }).
            where(PallasTrade::Product.property_conditions(property))
        end
      end

      base.add_search_scope :with_property_values do |property_filter_param, property_values|
        joins(product_properties: :property).
          where(PallasTrade::Property.table_name => { filter_param: property_filter_param }).
          where(PallasTrade::ProductProperty.table_name => { filter_param: property_values.map(&:parameterize) })
      end
    end

    def self.property_conditions(property)
      properties_table = PallasTrade::Property.table_name

      case property
      when PallasTrade::Property then { "#{properties_table}.id" => property.id }
      when Integer then { "#{properties_table}.id" => property }
      else
        if PallasTrade::Property.column_for_attribute('id').type == :uuid
          ["#{properties_table}.name = ? OR #{properties_table}.id = ?", property, property]
        else
          { "#{properties_table}.name" => property }
        end
      end
    end

    def property(property_name)
      if product_properties.loaded?
        product_properties.detect { |pp| pp.property.name == property_name }.try(:value)
      else
        product_properties.joins(:property).find_by(pallastrade_properties: { name: property_name }).try(:value)
      end
    end

    def set_property(property_name, property_value, property_presentation = property_name)
      property_name = property_name.to_s.parameterize
      ApplicationRecord.transaction do
        prop = if PallasTrade::Property.where(name: property_name).exists?
                 existing_property = PallasTrade::Property.where(name: property_name).first
                 existing_property.presentation ||= property_presentation
                 existing_property.save
                 existing_property
               else
                 PallasTrade::Property.create(name: property_name, presentation: property_presentation)
               end

        product_property = if PallasTrade::ProductProperty.where(product: self, property: prop).exists?
                             PallasTrade::ProductProperty.where(product: self, property: prop).first
                           else
                             PallasTrade::ProductProperty.new(product: self, property: prop)
                           end

        product_property.value = property_value
        product_property.save!
      end
    end

    def remove_property(property_name)
      product_properties.joins(:property).find_by(pallastrade_properties: { name: property_name.parameterize })&.destroy
    end

    def storefront_description
      property('short_description') || description
    end

    private

    def add_associations_from_prototype
      if prototype_id && (prototype = PallasTrade::Prototype.find_by(id: prototype_id))
        prototype.properties.each do |prop|
          product_properties.create(property: prop, value: 'Placeholder')
        end
        self.option_types = prototype.option_types
        self.taxons = prototype.taxons
      end
    end
  end
end

PallasTrade::Product.prepend(PallasTrade::ProductDecorator)
