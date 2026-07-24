module PallasTrade
  # Constant alias for PallasTrade::Searchable — remove in PallasTrade 6.0.
  #
  # Lets legacy code and extensions reference the concern by its former name
  # after the Searchable rename. The concern itself lives in PallasTrade::Searchable;
  # keeping the alias in its own file lets Zeitwerk manage (and reload) it,
  # avoiding the "already initialized constant" warning that a second constant
  # defined inside searchable.rb would raise.
  MultiSearchable = Searchable
end
