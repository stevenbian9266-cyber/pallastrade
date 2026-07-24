namespace :pallastrade do
  desc 'Loads sample data (products, customers, orders, configuration)'
  task load_sample_data: :environment do
    PallasTrade::SampleData::Loader.call
  end
end

# Backwards compatibility
namespace :pallastrade_sample do
  desc '[DEPRECATED] Use pallastrade:load_sample_data instead'
  task load: :environment do
    warn '[DEPRECATION] `rake pallastrade_sample:load` is deprecated. Use `rake pallastrade:load_sample_data` instead.'
    Rake::Task['pallastrade:load_sample_data'].invoke
  end
end
