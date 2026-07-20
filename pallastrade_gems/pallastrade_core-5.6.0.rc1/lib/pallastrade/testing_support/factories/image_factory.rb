FactoryBot.define do
  factory :image, class: PallasTrade::Asset do
    media_type { 'image' }

    before(:create) do |image|
      if image.class.method_defined?(:attachment)
        image.attachment.attach(io: File.new(PallasTrade::Core::Engine.root + 'spec/fixtures' + 'thinking-cat.jpg'), filename: 'thinking-cat.jpg')
      end
    end
  end
end
