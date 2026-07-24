require 'thor'
require 'thor/group'

case ARGV.first
when 'version', '-v', '--version'
  puts Gem.loaded_specs['pallastrade_extension'].version
when 'create'
  ARGV.shift
  require 'pallastrade_extension/extension'
  PallasTradeExtension::Extension.start
end
