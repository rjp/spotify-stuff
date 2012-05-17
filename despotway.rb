require 'rubygems'
require 'nokogiri'
require 'json'
require 'socket'
require 'xspf'

EncodeAlphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/";
EncodeHash = {}
EncodeAlphabet.split('').each_with_index {|l,i| EncodeHash[l] = i}

def id2uri(id)
    frombase = 16
    tobase = 62
    padlen = 22

    out = ' ' * padlen
    padlen = padlen - 1
    numbers = id.split('').map {|h| EncodeHash[h]}
    len = numbers.size

    loop do
        divide = 0
        newlen = 0

        0.upto(len-1) do |i|
            n = numbers[i]
            divide = divide * frombase + n
            if (divide > tobase) then
                numbers[newlen] = divide / tobase
                divide = divide % tobase

                newlen = newlen + 1
            elsif newlen > 0 then
                numbers[newlen] = 0
                newlen = newlen + 1
            end
        end
        len = newlen
        out[padlen] = EncodeAlphabet[divide]
        padlen = padlen - 1

        break if newlen == 0
    end

    return out
end

class Despot
    attr_accessor :username, :password, :host, :port
    attr_accessor :track_cache
    attr_accessor :socket, :playlists, :tracks

    def initialize(username, password, host, port)
        @host = host
        @port = port
        @username = username
        @password = password
        @socket = TCPSocket.new(host, port)
        @playlists = []
        @tracks = {}
        @track_cache = {}
    end

    def cmd(command, *params)
        cl = [command, params].flatten.join(' ') + "\n"
        $stderr.puts "> #{cl.inspect}"
        @socket.send(cl, 0)
        response = ""
        x = nil
        until x == "\n" do
            x = @socket.recv(1)
            response = response + x
        end
        $stderr.puts "< #{response.inspect}"
        code, length, status, text = response.split(' ', 4)
        if code.to_i != 200 then
# raise ArgumentError, text
            return [dom, code, length, status, text, payload]
        end
        payload = nil
        dom = nil
        if length.to_i > 0 then
            payload = @socket.read(length.to_i)
            dom = Nokogiri::XML(payload)
            if dom.nil? then
# raise ArgumentError, "XML does not parse"
            end
        end
        return [dom, code, length, status, text, payload]
    end

    def login
        r = self.cmd("login", @username, @password)
        $stderr.puts r.inspect
    end

    def load_playlists
        $stderr.puts("L /pl/all")
        dom, junk = self.cmd("playlist", "0000000000000000000000000000000000")
        playlist_ids = dom.at("//items").inner_text.strip.split(',')
        playlist_ids[0..2].each do |p|
            $stderr.puts("L /pl/#{p[0..33]}")
            self.load_playlist(p[0..33])
        end
    end

    def load_playlist(pid)
        dom, junk = self.cmd("playlist", pid)
if dom.nil? then
    raise ArgumentError, junk.inspect
end
        name = dom.at("//name").inner_text.strip
        # need the map/strip because occasional tids have a \n prefix
        track_ids = dom.at("//items").inner_text.strip.split(",").map{|tid| tid.strip}

        # local tracks get returned as "spotify:blah" IDs instead of hex
        local_tracks = track_ids.select {|tid| tid =~ /spotify:/}
        nonlocal_tracks = track_ids - local_tracks

        # look up the non-local tracks with the API
        tracks = nonlocal_tracks.map {|tid| self.load_track(tid[0..31])}
        if local_tracks.size > 0 then
            tracks << local_tracks
        end

        $stderr.puts "+ playlist #{name}"
        @playlists << {:name => name, :pid => pid, :tracks => tracks}
    end

    def load_track(tid)
        if not @track_cache[tid].nil? then
            return @track_cache[tid]
        end

        dom, junk = self.cmd("browsetrack", tid)

        track = {}
        success = dom.at("//total-tracks").inner_text.to_i

        if success > 0 then
            title = dom.at("//track/title").inner_text.strip
            artist = dom.at("//track/artist").inner_text.strip
            album = dom.at("//track/album").inner_text.strip
            index = dom.at("//track/track-number").inner_text.strip

            uri = id2uri(tid)

            track = {:title => title, :artist => artist, :album => album, :tid => tid, :uri => uri, :index => index}

            eid = dom.at("//track/external-ids/external-id")
            if not eid.nil? and eid['type'] == 'isrc' then
                track[:isrc] = eid['id']
            end

            $stderr.puts track.inspect
            @track_cache[tid] = track
        end

        return track
    end
end

# xspf blindly passes unescaped strings to eval in single quotes. Because ... yes. Why not.
class String
  def sq
    self.gsub(/'/, "\\\\'")
  end
end

config = JSON.load(open(ENV['HOME'] + '/.spotify.rb'))
username = config['username']
password = config['password']

# # #

# outputdir = ENV['HOME'] + '/playlists.xspf'
outputdir = './playlists.xspf'

begin
    Dir.mkdir(outputdir)
rescue
end

dsp = Despot.new(username, password, 'localhost', 9988)
dsp.login()
dsp.load_playlists()

dsp.playlists.each_with_index do |playlist, i|
    tl = XSPF::Tracklist.new()
    playlist[:tracks].each do |track|
        track[:to_link] = "spotify:track:" + track[:uri]
        # spotify:track:6sVQNUvcVFTXvlk3ec0ngd
        t = XSPF::Track.new( {
              :location => track[:to_link],
              :identifier => track[:to_link],
              :title => track[:title].sq,
              :creator => track[:artist].sq,
              :tracknum => track[:index].to_s,
              :album => track[:album].sq
            } )
        tl << t
    end

    xspf_pl = XSPF::Playlist.new( {
               :xmlns => 'http://xspf.org/ns/0/',
               :title => playlist[:name].sq,
               :creator => "Spotify/#{username}", # spotify link?
               :license => 'Redistribution or sharing not allowed',
               :info => 'http://www.example.com/',
               :tracklist => tl,
               :meta_rel => 'http://www.example.org/key',
               :meta_content => 'value'
             } )

    xspf = XSPF.new( { :playlist => xspf_pl } )
    safename = playlist[:name].gsub(/[^0-9a-zA-Z]/, "_")
    f = File.open(outputdir + "/playlist-#{username}-#{i}-#{safename}.xspf", 'w')
    f.write(xspf.to_xml)
    f.close
end

