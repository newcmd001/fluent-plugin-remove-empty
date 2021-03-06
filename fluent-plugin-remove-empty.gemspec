# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-remove-empty"
  gem.version     = "0.0.1"
  gem.authors     = ["Chadin Anuwattanaporn"]
  gem.email       = "chadin@sogamo.com"
  gem.homepage    = "https://github.com/newcmd001/fluent-plugin-remove-empty"
  gem.description = "Fluentd plugin to remove empty fields of a event record"
  gem.summary     = gem.description
  gem.licenses    = ["MIT"]
  gem.has_rdoc    = false

  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "fluentd", "~> 0.10.17"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-nav"
end
