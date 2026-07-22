Gem::Specification.new do |s|
  s.name        = 'pallastrade_posts'
  s.version     = '1.0.0'
  s.summary     = 'PallasTrade Posts — test fixture extension'
  s.description = 'Minimal extension gem used as a test fixture for PallasTrade extension testing.'
  s.authors     = ['PallasTrade']
  s.license     = 'MIT'
  s.require_paths = ['lib']
  s.add_dependency 'pallastrade', '>= 5.6'
  s.add_dependency 'pallastrade_admin', '>= 5.6'
end
