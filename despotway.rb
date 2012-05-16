require 'rubygems'
require 'nokogiri'
require 'json'
require 'socket'
require 'xspf'

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
        @playlists = {}
        @tracks = {}
        @track_cache = {}
    end

    def cmd(command, *params)
        cl = [command, params].flatten.join(' ') + "\n"
        puts "> #{cl.inspect}"
        @socket.send(cl, 0)
        response = ""
        x = nil
        until x == "\n" do
            x = @socket.recv(1)
            response = response + x
        end
        puts "< #{response.inspect}"
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
        p r
    end

    def load_playlists
        puts("L /pl/all")
        dom, junk = self.cmd("playlist", "0000000000000000000000000000000000")
        playlist_ids = dom.at("//items").inner_text.strip.split(',')
        playlist_ids.each do |p|
            puts("L /pl/#{p[0..33]}")
            self.load_playlist(p[0..33])
        end
    end

    def load_playlist(pid)
        dom, junk = self.cmd("playlist", pid)
        name = dom.at("//name").inner_text.strip
        track_ids = dom.at("//items").inner_text.strip.split(",")

        tracks = track_ids.map {|tid| self.load_track(tid[0..31])}

        @playlists[pid] = {:name => name, :tracks => tracks}
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

            track = {:title => title, :artist => artist, :album => album}

            eid = dom.at("//track/external-ids/external-id")
            if not eid.nil? and eid['type'] == 'isrc' then
                track[:isrc] = eid['id']
            end

            p track
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

outputdir = ENV['HOME'] + '/playlists.xspf'

begin
    Dir.mkdir(outputdir)
rescue
end

dsp = Despot.new(username, password, 'localhost', 9988)
dsp.login()
dsp.load_playlists()

dsp.playlists.each do |playlist, i|
    puts "#{i} #{playlist[:name]}"
end

