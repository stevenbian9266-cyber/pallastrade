require 'rails_helper'

RSpec.describe PallasTrade::Imports::RowProcessors::ProductVariant do
  subject(:processor) { described_class.allocate }

  before do
    allow(processor).to receive(:cached_lookup).and_yield
  end

  describe 'option lookup' do
    it 'matches option values by canonical name instead of a partial label' do
      option_type = create(:option_type, :color)
      create(:option_value, option_type: option_type, name: 'matte-black', presentation: 'Matte Black')

      option_value = processor.send(:find_or_create_option_value!, option_type, 'Black')

      expect(option_value.name).to eq('black')
      expect(option_type.option_values.pluck(:name)).to contain_exactly('matte-black', 'black')
    end
  end

  describe 'variant option replacement' do
    it 'destroys replaced joins instead of leaving rows without a variant' do
      variant = create(:variant)
      old_join_ids = variant.option_value_variants.ids
      replacement = create(:option_value)

      variant.option_value_variants = [
        PallasTrade::OptionValueVariant.new(variant: variant, option_value: replacement)
      ]

      expect(PallasTrade::OptionValueVariant.where(id: old_join_ids)).to be_empty
      expect(PallasTrade::OptionValueVariant.where(variant_id: nil)).to be_empty
      expect(variant.reload.option_values).to contain_exactly(replacement)
    end
  end
end
