require 'rubygems'
require 'nokogiri'
require 'json'
require 'socket'
require 'uri'
require 'open-uri'

### id2uri ## cargo-culted from lib/despotify.c

EncodeAlphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/";
EncodeHash = {}
EncodeAlphabet.split('').each_with_index {|l,i| EncodeHash[l] = i}

def baseconvert(input, frombase, tobase)
    padlen = 22

    out = ' ' * padlen
    padlen = padlen - 1
    numbers = input.split('').map {|h| EncodeHash[h]}
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

    # we might not have used up all 22 characters here
    # remove any prefixed whitespace (spotted by andym)
    return out.strip
end

def id2uri(input)
    return baseconvert(input, 16, 62)
end

def uri2id(input)
    return baseconvert(input, 62, 16)
end

### Despot ## our interface to despotify-gateway

class Despot
    attr_accessor :username, :password, :host, :port
    attr_accessor :track_cache, :outputdir, :metacache, :metafile
    attr_accessor :socket, :playlists, :tracks

    def initialize(username, password, host, port, outputdir)
        @host = host
        @port = port
        @username = username
        @password = password
        @outputdir = outputdir
        @metacache = {} # in-memory transient cache for now
        @socket = TCPSocket.new(host, port)
        @playlists = []
        @tracks = {}
        @track_cache = {}
    end

    def init_metacache
    end

    def album_metadata(aid)
        if not @metacache[aid].nil? then
            return @metacache[aid]
        end

        # not cached, we need to look it up from the web API
        aid_uri = id2uri(aid)
        $stderr.puts "W #{aid} #{aid_uri}"
        uri = "http://ws.spotify.com/lookup/1/?uri=spotify:album:#{aid_uri}"
        begin
            xml_meta = open(uri).read
        rescue
            $stderr.puts "!! http://ws.spotify.com/lookup/1/?uri=spotify:album:#{aid_uri} #{aid}"
            # return nil if we can't read from the API
            return nil
        end
        $stderr.puts xml_meta
        aid_meta = {}
        aid_meta[:id] = Hash.new()
        if not xml_meta.nil? then
            xml_dom = Nokogiri::XML(xml_meta)

            if xml_dom.nil? then
                return nil
            end

            # I hate having to do this
            xml_dom.remove_namespaces!

            # collect all the album metadata bits here
            xml_dom.search("/album/id").each do |idnode|
                id_type = idnode['type']
                aid_meta[:id][id_type] = idnode.inner_text.strip
            end
        else
            return nil
        end

        @metacache[aid] = aid_meta
        return aid_meta
    end

    def write_playlist(playlist)
        begin
            Dir.mkdir(@outputdir)
        rescue
        end

        pluri = id2uri(playlist[:pid][0..31])
        pl = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
            xml.playlist('version' => '1', 'xmlns' => 'http://xspf.org/ns/0/') {
                xml.title playlist[:name].to_s
                xml.creator "Spotify/#{username}" # spotify link?
                xml.info "http://open.spotify.com/user/#{playlist[:user]}"
                xml.location "http://open.spotify.com/user/#{playlist[:user]}/playlist/#{pluri}"
                xml.identifier "http://open.spotify.com/user/#{playlist[:user]}/playlist/#{pluri}"
                xml.meta Time.now.to_i, :rel => "http://frottage.org/xspf/created/epoch"
                xml.meta "despotway.rb", :rel => "http://frottage.org/xspf/creator"
                xml.trackList {
                    playlist[:tracks].each do |track|
                        # TODO refactor this out into a sanitising function
                        if track[:uri] =~ /^spotify/ then
                            track[:to_link] = track[:uri]
                        else
                            if track[:uri].nil? then # shouldn't happen because we protect against this in load_track
                                $stderr.puts "!! #{track.inspect} has no URI in output"
                                track[:uri] = "_daddy_"
                            end
                            track[:to_link] = "http://open.spotify.com/track/" + track[:uri]
                        end
                        xml.track {
                            xml.location track[:to_link]
                            xml.title track[:title].to_s
                            xml.creator track[:artist].to_s
                            xml.album track[:album].to_s
                            xml.duration track[:duration].to_s

                            # we don't always have an ISRC code
                            if not track[:isrc].nil? then
                                  xml.identifier "isrc:" + track[:isrc]
                            end

                            # do we have any album metadata to add?
                            if not track[:album_meta].nil? then
                                # we always have a :id subhash by design tho' it may be empty
                                track[:album_meta][:id].keys.each do |id_type|
                                    val = track[:album_meta][:id][id_type]
                                    # anything in the [:id] hash gets added as that type of identifier 
                                    if not val.nil? then
                                        xml.identifier "#{id_type}:#{val}"
                                    end
                                end
                            end

                            # we don't always have a track number
                            if not track[:index].nil? then
                                  xml.trackNum track[:index].to_s
                            end

                            # if we have :arid, this is a real Spotify track, add extra links for niceness
                            if not track[:arid].nil? then
                                xml.meta track[:arid], :rel => "http://frottage.org/xspf/spotify/artist-id"
                                xml.meta track[:aid], :rel => "http://frottage.org/xspf/spotify/album-id"
                                xml.meta track[:tid], :rel => "http://frottage.org/xspf/spotify/track-id"
                                l_artist = id2uri(track[:arid])
                                l_album = id2uri(track[:aid])
                                xml.meta "http://open.spotify.com/artist/#{l_artist}", :rel => "http://frottage.org/xspf/spotify/artist"
                                xml.meta "http://open.spotify.com/album/#{l_album}", :rel => "http://frottage.org/xspf/spotify/album"
                            end
                        }
                    end
                }
            }
        end

        safename = playlist[:name].gsub(/[^0-9a-zA-Z]/, "_")
        f = File.open(@outputdir + "/nokogiri-#{@username}-#{playlist[:pid]}-#{safename}.xspf", 'w')
        f.write(pl.to_xml)
        f.close
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

    def load_all_playlists
        $stderr.puts("L /pl/all")
        dom, junk = self.cmd("playlist", "0000000000000000000000000000000000")
        playlist_ids = dom.at("//items").inner_text.strip.split(',').map{|pid| pid.strip}

        self.load_playlists(playlist_ids)
    end

    def load_playlists(playlist_ids)
        playlist_ids.each do |p|
            $stderr.puts("L /pl/#{p[0..33]}")
            pl = self.load_playlist(p[0..33])
            if not pl.nil? then
                self.write_playlist(pl)
            end
        end
    end

    def load_playlist(pid)
        dom, junk = self.cmd("playlist", pid)
if dom.nil? then
    raise ArgumentError, junk.inspect
end
        user = dom.at("//user").inner_text.strip

#        if user != @username then
#            $stderr.puts "We don't handle subscribed playlists properly yet, sorry!"
#            return nil
#        end

        name = dom.at("//name").inner_text.strip
        # need the map/strip because occasional tids have a \n prefix
        track_ids = dom.at("//items").inner_text.strip.split(",").map{|tid| tid.strip}

        # fetch information about our tracks from the API (or not the API, depending)
        tracks = track_ids.map {|tid| self.load_track(tid)}

        $stderr.puts "+ playlist #{name}"
        x = {:name => name, :pid => pid, :tracks => tracks, :user => user}
        @playlists << x
        return x
    end

    def load_track(tid)
        if not @track_cache[tid].nil? then
            return @track_cache[tid]
        end

        if tid =~ /^spotify:local/ then
            # we can't look this track up remotely
            s, l, artist, album, title, duration = tid.split(/:/).map{|i| URI.unescape(i.gsub(/\+/,' '))}
            track = {:title => title, :artist => artist, :album => album, :tid => tid, :uri => tid, :duration => (1000*duration.to_i).to_s}
            @track_cache[tid] = track
            return track
        end

        if tid =~ /^spotify:track:(.*)/ then
            $stderr.puts "TU #{tid}"
        end

        # trim to 32 hex characters
        tid = tid[0..31]

        dom, junk = self.cmd("browsetrack", tid)

        track = {}
        success = dom.at("//total-tracks").inner_text.to_i

        if success > 0 then
            title = dom.at("//track/title").inner_text.strip
            artist = dom.at("//track/artist").inner_text.strip
            artist_id = dom.at("//track/artist-id").inner_text.strip
            album = dom.at("//track/album").inner_text.strip
            album_id = dom.at("//track/album-id").inner_text.strip
            index = dom.at("//track/track-number").inner_text.strip
            duration = dom.at("//track/length").inner_text.strip

            uri = id2uri(tid)
            if uri.nil? then
                $stderr.puts "!! #{tid} doesn't map to a URI somehow"
                uri = "_whoops_#{tid}_"
            end

            almeta = self.album_metadata(album_id)

            track = {:title => title, :artist => artist, :album => album, :tid => tid, :uri => uri, :index => index, :duration => duration, :aid => album_id, :album_meta => almeta, :arid => artist_id}

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

dsp = Despot.new(username, password, 'localhost', 9988, outputdir)
dsp.login()

if ARGV.size > 0 then # a list of playlist IDs
    dsp.load_playlists(ARGV)
else
    dsp.load_all_playlists()
end
