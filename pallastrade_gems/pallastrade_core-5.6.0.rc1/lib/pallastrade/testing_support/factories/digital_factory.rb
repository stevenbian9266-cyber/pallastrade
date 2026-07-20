FactoryBot.define do
  factory :digital, class: PallasTrade::Digital do
    after(:build) do |digital|
      digital.attachment.attach(io: File.new("#{PallasTrade::Core::Engine.root}/spec/fixtures/thinking-cat.jpg"),
                                filename: 'thinking-cat.jpg')
    end

    variant
  end
end
