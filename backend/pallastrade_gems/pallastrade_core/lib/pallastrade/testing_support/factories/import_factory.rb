FactoryBot.define do
  factory :import, class: 'PallasTrade::Import' do
    owner { PallasTrade::Store.default || create(:store) }
    association :user, factory: :admin_user
    type { 'PallasTrade::Imports::Products' }

    factory :product_import, class: 'PallasTrade::Imports::Products', parent: :import do
      type { 'PallasTrade::Imports::Products' }
      # attachment { Rack::Test::UploadedFile.new(PallasTrade::Core::Engine.root.join('spec', 'fixtures', 'files', 'products_import.csv'), 'text/csv') }

      after(:create) do |import|
        import.attachment.attach(
          io: File.open(PallasTrade::Core::Engine.root.join('spec', 'fixtures', 'files', 'products_import.csv')),
          filename: 'products_import.csv',
          content_type: 'text/csv'
        )
      end
    end

    factory :product_translation_import, class: 'PallasTrade::Imports::ProductTranslations', parent: :import do
      type { 'PallasTrade::Imports::ProductTranslations' }

      after(:create) do |import|
        import.attachment.attach(
          io: File.open(PallasTrade::Core::Engine.root.join('spec', 'fixtures', 'files', 'product_translations_import.csv')),
          filename: 'product_translations_import.csv',
          content_type: 'text/csv'
        )
      end
    end

    factory :customer_import, class: 'PallasTrade::Imports::Customers', parent: :import do
      type { 'PallasTrade::Imports::Customers' }

      after(:create) do |import|
        import.attachment.attach(
          io: File.open(PallasTrade::Core::Engine.root.join('spec', 'fixtures', 'files', 'customers_import.csv')),
          filename: 'customers_import.csv',
          content_type: 'text/csv'
        )
      end
    end
  end
end
