require 'optparse'
require 'json'

$options = {
    :host => 'localhost',
    :port => 9988,
    :login => nil,
    :config => ENV['HOME'] + '/.spotify.rb',
    :verbose => nil,
    :debug => nil,
    :playlist => nil,
    :outputdir => nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: despotlistback [-p port] [-h host] [-l username:password] [-v] [-d] [-p playlistid] [-o dir]"

  opts.on("-p", "--port N", Integer, "despotify-gateway port") do |p|
    $options[:port] = p
  end

  opts.on("-h", "--host HOST", String, "despotify-gateway host") do |p|
    $options[:host] = p
  end

  opts.on("-l", "--login USERNAME:PASSWORD", String, "Spotify login") do |p|
    $options[:login] = p
  end

  opts.on("-c", "--config CONFIG", String, "config file") do |p|
    $options[:config] = p
  end

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    $options[:verbose] = v
  end

  opts.on("-d", "--[no-]debug", "Output debugging") do |v|
    $options[:debug] = v
  end

  opts.on("-p", "--playlist playlistid[,playlistid]", String, "Playlist ID(s)") do |p|
    $options[:playlist] = p
  end

  opts.on("-o", "--output", String, "Output directory") do |o|
    $options[:output] = o
  end

end.parse!

if $options[:login].nil? then
    if $options[:config].nil? then
        $stderr.puts "Must specify either --login or --config"
        exit
    end
end

# TODO handle failing here with exceptions
config = JSON::load(open($options[:config]))

# merge the whole of the config file into the $options hash
config.each { |k,v|
    $options[k.to_sym] = v
}

# We've got here through the config file
if $options[:login].nil? then
    if $options[:username].nil? or $options[:password].nil? then
        $stderr.puts "Config file is not well-specified"
        exit
    end

    $options[:login] = [$options[:username], $options[:password]].join(':')
end
