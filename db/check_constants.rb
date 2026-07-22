puts "Legacy PallasTrade constant defined: #{Object.const_defined?(:PallasTrade, false)}"
puts "PallasTrade constant defined: #{Object.const_defined?(:PallasTrade, false)}"
abort('FAIL: Legacy PallasTrade constant still exists!') if Object.const_defined?(:PallasTrade, false)
abort('FAIL: PallasTrade constant missing!') unless Object.const_defined?(:PallasTrade, false)
puts 'PASS: PallasTrade constants verified'
