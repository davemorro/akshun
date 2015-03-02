#!/usr/bin/env ruby
# -*- coding: utf-8 -*- #specify UTF-8 (unicode) characters

# akshun.rb is a command-line script that uses Seatgeek to find gigs in your area and 
# add them to an Rdio playlist. 
#
# Akshun defaults to finding music events for the next 7 days within 12 miles of 
# your current location (as determined by your external IP Address)
# 
# Before running:
# Update 'rdio_consumer_credentials.rb' with your Rdio developer credentials. See 
# http://www.rdio.com/developers/
# 
# To run:
# ruby akshun.rb
#
# The following override options are available:
#   -l: location   US or CA Zip Code or IP Address
#   -r: range      Range in miles
#   -f: from_date  From date (uses Chronic for nlp)
#   -p: period     Period in days
#
# Requires 'om.rb', 'rdio.rb', and 'rdio_consumer_credentials.rb' to exist in same directory

$LOAD_PATH << ''
require "rubygems"
require "yaml"
require "trollop"
require "chronic"
require "seatgeek"
require 'rdio'
require 'rdio_consumer_credentials'
require 'open-uri'

module Akshun
    def self.init(args)
        @@rdio = Rdio.new([RDIO_CONSUMER_KEY, RDIO_CONSUMER_SECRET])
        
        opts = Trollop::options do
            opt :location, "IP Address or US/CA Zip", :short => "-l", :type => :string, :default => open('http://whatismyip.akamai.com').read
            opt :range, "Range (Miles)", :short => "-r", :type => :integer, :default => 12
            opt :from, "From Date", :short => "-f", :type => :string, :default => Date.today.to_s
            opt :period, "Period (Days)", :short => "-p", :type => :integer, :default => 7
            stop_on_unknown
        end
        
        opts[:from] = Chronic.parse(opts[:from]).to_date
        opts[:to] = opts[:from] + opts[:period]
        opts[:range] = "#{opts[:range]}mi"
        
        process(opts)
    end
    
    def self.process(opts)
        options = {
            :geoip => opts[:location], 
            :range => opts[:range], 
            "taxonomies.name" => "concert", 
            "datetime_utc.gte" => opts[:from], 
            "datetime_utc.lte" => opts[:to], 
            :per_page => 400
        }
        
        results = SeatGeek::Connection.events(options)
        abort "Seatgeek service unavailable" if results[:status]
        
        puts "#{results["meta"]["total"]} events found within #{results["meta"]["geolocation"]["range"]} of #{results["meta"]["geolocation"]["postal_code"]} between #{opts[:from]} and #{opts[:to]}"
        
        tracks_arr = []
    
        results["events"].each do |event|
            puts "# #{event["title"].upcase}\n"
            event["performers"].each do |performer|            
                artists = @@rdio.call('search', { :query => performer["name"], :types => "artist" })["result"]
                
                artist_key = artists["results"].empty? ? nil : artists["results"].first["key"]
                artist_tracks_keys = []
                unless artist_key.nil?
                    artist_tracks = @@rdio.call('getTracksForArtist', {:artist => artist_key, :count => 2})
                    artist_tracks_keys = artist_tracks["result"].map{|t| t["key"]} unless artist_tracks.empty?
                    tracks_arr.push(artist_tracks_keys)
                end
                
                puts "* #{performer["name"]} (#{artist_tracks_keys.size} tracks on Rdio)"
                    
            end
            puts ""
            puts event["datetime_local"]
            puts event["venue"]["name"]
            puts [event["venue"]["address"], event["venue"]["city"]].compact.join(", ")
            puts "----\n"
        end
        
        playlist_key = reset_playlist(opts[:from], opts[:to], results["meta"]["geolocation"]["postal_code"], results["meta"]["geolocation"]["range"])
        add_to_playlist(tracks_arr, playlist_key) unless tracks_arr.empty?
    end
    
    def self.reset_playlist(from, to, location, range)
        check_authorization
        
        playlists = @@rdio.call('getPlaylists')
        akshun_playlist = playlists["result"]["owned"].find { |h| h['name'] === 'Akshun' }
        
        unless akshun_playlist.nil?
            puts "Found Playlist. Deleting"
            playlist_key = akshun_playlist["key"]
            @@rdio.call('deletePlaylist', {:playlist => playlist_key})
        end
        
        puts "Creating Playlist"
        res = @@rdio.call('createPlaylist', {:name => "Akshun", :description => "Artists performing within #{range} of #{location} between #{from.strftime("%A %B %d, %Y")} and #{to.strftime("%A %B %d, %Y")}", :isPublished => "true", :tracks => ""})
        
        return res["result"]["key"]
    end
    
    def self.add_to_playlist(track_keys, playlist_key)
        puts "Adding #{track_keys.size} tracks to Akshun playlist"
        res = @@rdio.call('addToPlaylist', {:playlist => playlist_key, :tracks => track_keys})
        
        puts res
    end
    
    def self.check_authorization
        res = @@rdio.call('getPlaylists')
        authorize if res["status"] == "error"
    end
        
    def self.authorize
        url = @@rdio.begin_authentication('oob')
        puts 'Go to: ' + url
        print 'Then enter the code: '
        verifier = gets.strip
        @@rdio.complete_authentication(verifier)
    end
end

if __FILE__ == $0
    Akshun.init ARGV
end
