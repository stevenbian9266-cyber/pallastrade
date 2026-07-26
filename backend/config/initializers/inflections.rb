# frozen_string_literal: true

# Add custom acronyms for the PallasTrade application.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  # AI = Artificial Intelligence (not "Ai")
  inflect.acronym 'AI'
end
