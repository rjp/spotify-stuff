require 'rubygems'
require 'hallon'
require 'xspf'
require 'json'

# xspf blindly passes unescaped strings to eval in single quotes. Because ... yes. Why not.
class String
  def sq
    self.gsub(/'/, "\\\\'")
  end
end

config = JSON.load(open(ENV['HOME'] + '/.spotify.rb'))
username = config['username']

session = Hallon::Session.initialize IO.read(config['appkey']) do
on(:log_message) do |message|
puts "[LOG] #{message}"
end

    on(:connection_error) do |error|
Hallon::Error.maybe_raise(error)
    end

    on(:logged_out) do
    abort "[FAIL] Logged out!"
    end
    end

session.login!(config['username'], config['password'])

puts "Successfully logged in!"

user = Hallon::User.new(ARGV[0] || config['username'])
username = user.name
published = user.published
session.wait_for { published.loaded? }

puts "Listing #{published.size} playlists."
published.contents.each_with_index do |playlist, i|
    next if playlist.nil? # folder or somesuch

    session.wait_for { playlist.loaded? }

    f = "spotify_playlist_#{username}_#{i}.xspf"
    tl = XSPF::Tracklist.new()

    puts
    puts playlist.name << ": "

    playlist.tracks.each_with_index do |track, i|
        session.wait_for { track.loaded? }

        puts "\t (#{i+1}/#{playlist.size}) #{track.name}"
        
# Add it to our XSPF Tracklist
        t = XSPF::Track.new( {
              :location => track.to_link,
              :identifier => track.to_link.to_str,
              :title => track.name.sq,
              :creator => track.artist.name.sq,
              :tracknum => track.index.to_s,
              :album => track.album.name.sq
            } )
        tl << t
    end

    xspf_pl = XSPF::Playlist.new( {
               :xmlns => 'http://xspf.org/ns/0/',
               :title => playlist.name,
               :creator => "Spotify/#{username}", # spotify link?
               :license => 'Redistribution or sharing not allowed',
               :info => 'http://www.example.com/',
               :tracklist => tl,
               :meta_rel => 'http://www.example.org/key',
               :meta_content => 'value'
             } )

    xspf = XSPF.new( { :playlist => xspf_pl } )

    f = File.open("playlist_#{username}_#{i}.xspf", 'w')
    f.write(xspf.to_xml)
    f.close

end
