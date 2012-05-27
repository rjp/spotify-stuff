# Output our collection of tracks as an XSPF-compliant playlist.
#
# [xspf]: http://xspf.org/xspf-v1.html
# [notes]: http://wiki.xiph.org/XSPF_v1_Notes_and_Errata
# [xspfgem]: http://xspf.rubyforge.org/
#
# Because we want to use multiple <meta> and <identifier> elements, we can't use the [xspf gem][xspfgem].
# In lieu of a proper libxspf based alternative, we use Nokogiri::XML::Builder to construct our XML output.

require 'rubygems'
require 'nokogiri'
require 'fileutils'

# We'll be adding "proper" Spotify links for track, user, artist, album which means we need to be able to
# convert the 16 byte API IDs into the Base 62 encoded IDs.
require 'despotlistback/convert'

# All our <meta> elements are versioned - see the [xspf notes][notes].
MetaBase = "http://frottage.org/xspf/spotify/"
MetaVer = "/1/0"

def metauri(key)
    return MetaBase + key + MetaVer
end

# "Naming is hard".
class DespoGClient
    def write_playlist(playlist)
        # Technically this is redundant since we do this later on. FIXME
        begin
            FileUtils.mkdir_p(@outputdir)
        rescue
        end

        pluri = id2uri(playlist.id[0..31])

        pl = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
            xml.playlist('version' => '1', 'xmlns' => 'http://xspf.org/ns/0/') {
                xml.title playlist.name.to_s
                xml.creator "Spotify/#{username}" # spotify link?
                xml.info "http://open.spotify.com/user/#{playlist.author}"
                xml.location "http://open.spotify.com/user/#{playlist.author}/playlist/#{pluri}"
                xml.identifier "http://open.spotify.com/user/#{playlist.author}/playlist/#{pluri}"
                xml.meta Time.now.to_i, :rel => metauri("epoch")
                xml.meta "despotway.rb", :rel => metauri("creator")
                xml.trackList {
                    playlist.tracks.each do |track|
                        to_link = nil
                        p track['id']
                        if track['id'] =~ /spotify:local/ then
                            s, l, artist, album, title, duration = track['id'].split(/:/).map{|i| URI.unescape(i.gsub(/\+/,' '))}
                            b = {:title => title, 'artists' => [artist], :album => album, :id => track['id'], :uri => track['id'], :length => (1000*duration.to_i).to_s}
                            xml.track {
                                xml.location track['id']
                                xml.title title.to_s
                                xml.creator artist.to_s
                                xml.album album.to_s
                                xml.duration (1000*duration.to_i).to_s
                            }
                            next
                        end

                        track.metadata['album_meta'] = self.album_metadata(track['album_id'])

                        uri = id2uri(track['id'])
                        to_link = "http://open.spotify.com/track/" + uri
                        p track.metadata
                        artist = track.artists.first # meh

                        xml.track {
                            xml.location to_link
                            xml.location track.to_uri
                            xml.title track['title'].to_s
                            xml.creator artist['name'].to_s
                            xml.album track['album'].to_s
                            xml.duration track['length'].to_s

                            # we don't always have an ISRC code
                            track['external_ids'].each do |k,v|
                                xml.identifier "#{k}:" + v
                            end

#                            # do we have any album metadata to add?
                            if not track['album_meta'].nil? then
                                # we always have a :id subhash by design tho' it may be empty
                                track['album_meta']['external_ids'].each do |id_type, val|
                                    # anything in the [:id] hash gets added as that type of identifier
                                    if not val.nil? and not val.empty? then
                                        xml.identifier "#{id_type}:#{val}"
                                    end
                                end
                            end

                            # we don't always have a track number
                            if not track.tracknumber.nil? then
                                  xml.trackNum track.tracknumber.to_s
                            end

                            # if we have :arid, this is a real Spotify track, add extra links for niceness
                            if not artist['id'].nil? then
                                xml.meta artist.id, :rel => metauri("artist-id")
                                xml.meta track['album_id'], :rel => metauri("album-id")
                                xml.meta track.id, :rel => metauri("track-id")
                                l_artist = id2uri(artist.id)
                                l_album = id2uri(track.album_id)
                                xml.meta "http://open.spotify.com/artist/#{l_artist}", :rel => metauri("artist")
                                xml.meta "http://open.spotify.com/album/#{l_album}", :rel => metauri("album")
                            end
                        }
                    end
                }
            }
        end

        safename = playlist.name.gsub(/[^0-9a-zA-Z]/, "_")

        replace = {
            "%u" => @username,
            "%c" => playlist.author,
            "%w" => [@username, playlist.author].uniq.join(':'),
            "%i" => playlist.id,
            "%s" => playlist.tracks.size.to_s,
            "%d" => playlist.author == @username ? "" : "subscribed/",
            "%n" => safename
        }

        filename = "#{$options[:format]}"
        replace.each do |k,v|
            filename.gsub!(k, v)
        end

        path = @outputdir + "/" + filename
        basedir = File.dirname(path)

        begin
            FileUtils.mkdir_p(basedir)
        rescue
        end

        f = File.open(@outputdir + "/#{filename}", "w")
        f.write(pl.to_xml)
        f.close
    end
end
