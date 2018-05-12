require 'twitter'
require 'YAML'
require 'JSON'
require 'fileutils'
#require 'aws-sdk'
require 'date'
require 'digest/sha1'
require "slack-ruby-client"
require File.expand_path(File.dirname(__FILE__)) + '/mRandelbot'
require File.expand_path(File.dirname(__FILE__)) + '/albums'

include Albums

COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/
PIXEL_COORDS_REGEX = /(\d+),(\d+)/

def generate_image m, next_point, album
    album_base_path = get_album_base_path(m, album)
    `#{m.config["mandelbrot"]} -z=#{next_point[:zoom]} -r=#{next_point[:coords][0]} -i=#{next_point[:coords][1]} -c=true -o=#{album_base_path} -g='#{album[:gradient]}'`.chomp
end

def seed_points_up_to m, seed_until
    r = -0.75
    i = 0
    z = 1

    r, i = get_a_point m, -0.75, 0, 1
        
    z *= seed_until + rand() * 4 + 2

    return r,i,z
end

def get_a_point m, real, imaginary, zoom
    result = `#{m.config["mandelbrot"]} -o=#{m.base_path} -f=tmp.jpg -z=#{zoom} -r=#{real} -i=#{imaginary}`.chomp
    pixels = `convert #{result} -canny 0x1+10%+30% -write TXT:- | grep "#FFF" | gshuf -n 1 | awk -F':' '{print $1}'`.chomp
   
    if PIXEL_COORDS_REGEX.match(pixels)
        parsed_pixels  = pixels.scan(PIXEL_COORDS_REGEX)[0]
        coords = `#{m.config["mandelbrot"]} -mode=coordsAt -z=#{zoom} -r=#{real} -i=#{imaginary} -x=#{parsed_pixels[0]} -y=#{parsed_pixels[1]}`.chomp
        if COORDS_REGEX.match(coords)
            parsed_coords = coords.scan(COORDS_REGEX)[0]
            return parsed_coords[0], parsed_coords[1] 
        end
    end

    return nil, nil
end

def add_meta_data filename, exiftool, point
    real, imaginary, zoom = get_point_coordinate_and_zoom(point)

    `#{exiftool} -gps:GPSLongitude="#{real}" #{filename}`
    `#{exiftool} -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0
    
    `#{exiftool} -gps:GPSLatitude="#{imaginary}" #{filename}`
    `#{exiftool} -gps:GPSLatitudeRef="S" file` if imaginary.to_f < 0
    
    `#{exiftool} -DigitalZoomRatio="#{zoom}" #{filename}`
    `#{exiftool} exiftool -delete_original! #{filename}`
end

def get_next_point album
    points = album[:points].map{ |p| p.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}}
    return points.keep_if{ |p| p[:generatedAt] == ""}.sort{|p1,p2| p1[:createdAt] <=> p2[:createdAt]}.first
end

def get_album_base_path m, album
    album_base_path = File.join(m.base_path, album[:album])
end

def create_a_new_album m
    a = create_album
    album_base_path = get_album_base_path(m, a)
    Dir.mkdir(album_base_path) if !Dir.exists?(album_base_path)
    a[:gradient] = m.generate_gradient

    real, imaginary, zoom = seed_points_up_to m, 50

    a[:points] << create_point(real, imaginary, zoom)
    
    a
end

def create_point(real, imaginary, zoom)
    return {zoom: zoom, coords: [real, imaginary], published: false, generatedAt: "", createdAt: DateTime.now.strftime("%Y%m%d%H%M%S")}
end

def get_an_album m
    active_albums = get_active_albums

    # To keep things interesting, we pick an album at random.
    # To ensure we don't always just have one album, we also allow
    # for two extra slots, and if one of those slots is chosen, we
    # create a new album
    album_to_use = rand() * (active_albums.size) + 2

    return create_a_new_album(m) if (album_to_use >= active_albums.size)

    return get_album(active_albums[album_to_use])
end

def get_new_plot_details m, last_plot
    real, imaginary, zoom = nil
    if !last_plot
        real, imaginary, zoom = seed_points_up_to m, 50
    else
        r,i,z = get_point_coordinate_and_zoom last_plot
        
        real, imaginary = get_a_point m, r, i, z
        zoom = z.to_f * (rand() * 4 + 2)
    end

    return real, imaginary, zoom
end

def get_point_coordinate_and_zoom point
    real = point[:coords][0]
    imaginary = point[:coords][1]
    zoom = point[:zoom]

    return real, imaginary, zoom        
end

def publish_to_slack(m, filename, point)
    Slack.configure do |slack|
        slack.token = m.config["slack"]["token"]
    end

    client = Slack::Web::Client.new
    real, imaginary, zoom = get_point_coordinate_and_zoom(point)
    
    return client.files_upload(
        channels: '#logs',
        as_user: true,
        file: Faraday::UploadIO.new(filename, 'image/jpeg'),
        title: "#{real} + #{imaginary}i at zoom #{'%.10e' % zoom}",
        filename: filename,
    )
end

def publish_to_twitter(m, filename, point)
    client = Twitter::REST::Client.new do |twitter|
        twitter.consumer_key = m.config["twitter"]["CONSUMER_KEY"]
        twitter.consumer_secret = m.config["twitter"]["CONSUMER_SECRET"]
        twitter.access_token = m.config["twitter"]["OAUTH_TOKEN"]
        twitter.access_token_secret = m.config["twitter"]["OAUTH_TOKEN_SECRET"]
    end

    real, imaginary, zoom = get_point_coordinate_and_zoom(point)

    id 
    File.open(filename, "r") do |file|
        tweet = client.update_with_media("#{real} + #{imaginary}i at zoom #{'%.10e' % zoom}", file, {:lat=>imaginary, :long=>real, :display_coordinates=>'true'})
        id = tweet.id
    end

    return id
end

m = Mrandelbot.new

album = get_an_album(m)

point_to_generate = get_next_point(album)

filename = generate_image(m, point_to_generate, album)

# apply meta data
add_meta_data filename, m.config["exiftool_path"], point_to_generate

# publish
slack_file = publish_to_slack(m, filename, point_to_generate)

if m.config["mode"] != "DEV"
    tweet_id = publish_to_twitter m, filename, point_to_generate
    point_to_generate["tweet"] = tweet_id
end

# update plot as generated
point_to_generate["published"] = true
point_to_generate["generatedAt"] = DateTime.now.strftime("%Y%m%d%H%M%S")

# Queue up the next plot for this album
next_real, next_imaginary, next_zoom = get_new_plot_details(m, point_to_generate)

# max zoom level arbitrarily chosen max zoom level based on trial and error
# nil real implies no point was returned because no edge point exists
if next_zoom > 10**14 || next_real == nil
    archive_album(album)
    exit
end

next_point = create_point(next_real, next_imaginary, next_zoom)

album[:points] << next_point
save_album(album)



