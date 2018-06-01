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
require File.expand_path(File.dirname(__FILE__)) + '/gradient_gen'

include Albums

COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/
PIXEL_COORDS_REGEX = /(\d+),(\d+)/



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
    point_to_generate[:tweet] = tweet_id
end

# update plot as generated
point_to_generate[:published] = true
point_to_generate[:generatedAt] = DateTime.now.strftime("%Y%m%d%H%M%S")

album = update_point album, point_to_generate

# Queue up the next plot for this album
next_real = 0.0
next_imaginary = 0.0
next_zoom = 0.0

while next_imaginary == 0.00 do
    next_real, next_imaginary, next_zoom = get_new_plot_details(m, point_to_generate)
end

# max zoom level arbitrarily chosen max zoom level based on trial and error
# nil real implies no point was returned because no edge point exists
if next_zoom > 10**14 || next_real == nil
    archive_album(album)
    exit
end

next_point = create_point(next_real, next_imaginary, next_zoom)

album[:points] << next_point
save_album(album)