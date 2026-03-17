Gem::Specification.new do |s|
  s.name        = "transit-at"
  s.version     = "0.1.0"
  s.summary     = "Austrian public transit delay data from the command line"
  s.description = "CLI for querying real-time delay statistics across 20 Austrian cities. Wraps the ÖBB HAFAS API with derived delay analytics."
  s.authors     = ["Haumer"]
  s.homepage    = "https://github.com/Haumer/wiener_linien_delays"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.1"

  s.files       = Dir["lib/**/*.rb", "bin/*"]
  s.bindir      = "bin"
  s.executables = ["transit"]

  s.add_dependency "json"
end
