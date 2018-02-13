require 'twitter'
require 'YAML'
require 'JSON'
require 'fileutils'
#require 'aws-sdk'
require 'date'
require 'digest/sha1'
require "slack-ruby-client"
require File.expand_path(File.dirname(__FILE__)) + '/mRandelbot'


COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/

def seed_points_up_to m, seed_until
    r = -0.75
    i = 0
    z = 1

    while z < seed_until
        r, i = get_a_point m, r, i, z
        
        z *= rand() * 4 + 2
    end

    return r,i,z
end

def get_a_point m, real, imaginary, zoom
    result = `#{m.config["mandelbrot"]} -mode=edge -w=1000 -h=1000 -z=#{zoom} -r=#{real} -i=#{imaginary}`.chomp
    parsed_coords  = result.scan(COORDS_REGEX)[0]
    if COORDS_REGEX.match(result)
        return parsed_coords[0], parsed_coords[1] 
    end

    return nil, nil
end

def add_meta_data filename, exiftool, real, imag, zoom
    
      `#{exiftool} -gps:GPSLongitude="#{real}" #{filename}`
      `#{exiftool} -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0
    
      `#{exiftool} -gps:GPSLatitude="#{imag}" #{filename}`
      `#{exiftool} -gps:GPSLatitudeRef="S" file` if imag.to_f < 0
    
      `#{exiftool} -DigitalZoomRatio="#{zoom}" #{filename}`
      `#{exiftool} exiftool -delete_original! #{filename}`
end

m = Mrandelbot.new

a = m.get_album

base_path = File.join(m.base_path, a[:album])

Dir.mkdir(base_path) if !Dir.exists?(base_path)

plot = a[:points].sort{|p1,p2| p1["createdAt"] <=> p2["createdAt"]}.last
real, imaginary, zoom = nil
if !plot
    real, imaginary, zoom = seed_points_up_to m, 50
else
    z = plot["zoom"]
    r = plot["coords"][0]
    i = plot["coords"][1]
    
    real, imaginary = get_a_point m, r, i, z
    zoom = z.to_f * (rand() * 4 + 2)
end

# max zoom level arbitrarily chosen max zoom level based on trial and error
# nil real implies no point was returned because no edge point exists
if zoom > 10**14 || real == nil
    
    m.archive_album a
    a = m.get_album
    Dir.mkdir(base_path) if !Dir.exists?(base_path)
    real, imaginary, zoom = seed_points_up_to m, 50
end

plot = {zoom: zoom, coords: [real, imaginary], published: false, createdAt: DateTime.now.strftime("%Y%m%d%H%M%S")}

filename = `#{m.config["mandelbrot"]} -z=#{zoom} -r=#{real} -i=#{imaginary} -c=true -o=#{base_path} -g='#{a[:gradient]}'`.chomp
plot[:filename] = filename
m.save_album a

add_meta_data filename, m.config["exiftool_path"], real, imaginary, zoom

Slack.configure do |slack|
    slack.token = m.config["slack"]["token"]
end

client = Slack::Web::Client.new

client.files_upload(
  channels: '#logs',
  as_user: true,
  file: Faraday::UploadIO.new(filename, 'image/jpeg'),
  title: "#{real} + #{imaginary}i at zoom #{'%.10e' % zoom}",
  filename: filename,
)
if m.config["mode"] != "DEV"
    client = Twitter::REST::Client.new do |twitter|
        twitter.consumer_key = m.config["twitter"]["CONSUMER_KEY"]
        twitter.consumer_secret = m.config["twitter"]["CONSUMER_SECRET"]
        twitter.access_token = m.config["twitter"]["OAUTH_TOKEN"]
        twitter.access_token_secret = m.config["twitter"]["OAUTH_TOKEN_SECRET"]
    end
 
    File.open(filename, "r") do |file|
        tweet = client.update_with_media("#{real} + #{imaginary}i at zoom #{'%.10e' % zoom}", file, {:lat=>imaginary, :long=>real, :display_coordinates=>'true'})
        plot[:tweet] = tweet.id
        m.save_album a
    end
end

plot[:published] = true
a[:points] << plot
m.save_album a


