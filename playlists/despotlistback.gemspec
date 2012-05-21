spec = Gem::Specification.new do |s| 
  s.name = "despotlistback"
  s.version = "0.0.3"
  s.author = "Rob Partington"
  s.email = "rjpartington@gmail.com"
  s.homepage = "http://rjp.github.com/spotify-stuff"
  s.platform = Gem::Platform::RUBY
  s.summary = "Simple Spotify playlist backup"
  s.description = "Backup your Spotify playlists to XSPF files using despotify-gateway"
  s.files = ['bin/despotlistback', 'lib/despotlistback/options.rb', 'lib/despotlistback/convert.rb', 'lib/despotlistback/xspf.rb']
  s.require_path = "lib"
  s.test_files = []
  s.add_dependency('nokogiri')
  s.add_dependency('json')
  s.executables = ['despotlistback']
  s.has_rdoc = true
  s.extra_rdoc_files = [
    "README.txt"
  ]
  s.rubyforge_project = 'despotlistback'
end

