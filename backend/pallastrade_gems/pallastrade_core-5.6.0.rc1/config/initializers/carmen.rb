# Patches Carmen::Querying#normalise_name to avoid the deprecated
# ActiveSupport::Multibyte::Chars API (mb_chars), which will be removed in
# Rails 8.2.
#
# In Ruby 2.4+, String#downcase is already Unicode-aware, making the mb_chars
# call redundant. Since PallasTrade requires Ruby >= 3.2, we can drop it safely.
#
# This patch can be removed once the dependency is fixed.
#
# See: https://github.com/carmen-ruby/carmen/issues/304
require 'carmen'

module PallasTrade
  module CarmenQueryingPatch
    private

    def normalise_name(name)
      name.downcase.unicode_normalize(:nfkc)
    end
  end
end

Carmen::Querying.prepend(PallasTrade::CarmenQueryingPatch)
