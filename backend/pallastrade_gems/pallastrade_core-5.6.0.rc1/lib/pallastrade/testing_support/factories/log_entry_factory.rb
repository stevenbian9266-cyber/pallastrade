FactoryBot.define do
  factory :log_entry, class: PallasTrade::LogEntry do
    source { build(:order) }
    details { 'Some details' }
  end
end
