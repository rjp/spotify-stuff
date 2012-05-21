require 'rubygems'
require 'nokogiri'
require 'despotlistback/convert'

class Despot
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
end
