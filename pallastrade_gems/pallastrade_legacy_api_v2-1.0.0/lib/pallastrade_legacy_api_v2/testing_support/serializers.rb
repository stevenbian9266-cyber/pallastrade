module PallasTrade
  class TestArgumentsJob < PallasTrade::BaseJob
    def perform(serializer); end
  end
end

shared_examples 'an ActiveJob serializable hash' do
  it 'can be serialized by ActiveJob' do
    # It should fail if subject contains any custom instance (e.g PallasTrade::Money)
    expect { PallasTrade::TestArgumentsJob.perform_later(subject) }.not_to raise_error
    expect { PallasTrade::TestArgumentsJob.perform_later(subject.merge(price: PallasTrade::Money.new(0))) }.to(
      raise_error(ActiveJob::SerializationError)
    )
  end
end
