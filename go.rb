require "twitter"
require "yaml"
require "json"
require "fileutils"
#require 'aws-sdk'
require "date"
require "digest/sha1"
require "slack-ruby-client"
require File.expand_path(File.dirname(__FILE__)) + "/mRandelbot"
require File.expand_path(File.dirname(__FILE__)) + "/albums"
require File.expand_path(File.dirname(__FILE__)) + "/gradient_gen"

include Albums

COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/
PIXEL_COORDS_REGEX = /(\d+),(\d+)/

def publish_to_slack(m, filename, point, series)
  return unless ENV["MRANDELBOT_SLACK_POST"]
  p "Posting to Slack"
  Slack.configure do |slack|
    slack.token = ENV["MRANDELBOT_SLACK_API_TOKEN"]
  end

  client = Slack::Web::Client.new
  real, imaginary, zoom = get_point_coordinate_and_zoom(point)

  return client.files_upload(
           channels: "#logs",
           as_user: true,
           file: Faraday::UploadIO.new(filename, "image/jpeg"),
           title: "#{real} + #{imaginary}i at zoom #{"%.10e" % zoom}. jit:#{series}",
           filename: filename,
         )
end

def publish_to_twitter(m, filename, point, series)
  return unless ENV["MRANDELBOT_TWITTER_POST"]
  p "Posting to Twitter"

  client = Twitter::REST::Client.new do |twitter|
    twitter.consumer_key = ENV["MRANDELBOT_TWITTER_CONSUMER_KEY"]
    twitter.consumer_secret = ENV["MRANDELBOT_TWITTER_CONSUMER_SECRET"]
    twitter.access_token = ENV["MRANDELBOT_TWITTER_OAUTH_TOKEN"]
    twitter.access_token_secret = ENV["MRANDELBOT_TWITTER_OAUTH_TOKEN_SECRET"]
  end

  real, imaginary, zoom = get_point_coordinate_and_zoom(point)

  id = nil
  File.open(filename, "r") do |file|
    tweet = client.update_with_media("#{real} + #{imaginary}i at zoom #{"%.10e" % zoom}. jit:#{series}", file, { :lat => imaginary, :long => real, :display_coordinates => "true" })
    id = tweet.id
  end

  return id
end

m = Mrandelbot.new

Albums.configure do |c|
  c.database_path = ENV["MRANDELBOT_DATABASE_PATH"]
end

album = get_an_album(m)

point_to_generate = get_next_point(album).first

if point_to_generate == nil
  p "seeding new point"
  real, imaginary, zoom = seed_points_up_to m, 50

  point_to_generate = create_point(real, imaginary, zoom)
end

filename = generate_image(m, point_to_generate, album)

# apply meta data
add_meta_data filename, point_to_generate

# publish
slack_file = publish_to_slack(m, filename, point_to_generate, album["name"])
tweet_id = publish_to_twitter m, filename, point_to_generate, album["name"]
point_to_generate[:tweet] = tweet_id

# update plot as generated
point_to_generate["published"] = true
point_to_generate["generatedAt"] = DateTime.now.strftime("%Y%m%d%H%M%S")

point = update_point album, point_to_generate

# Queue up the next plot for this album
next_real = 0.0
next_imaginary = 0.0
next_zoom = 0.0

while next_imaginary == 0.00
  next_real, next_imaginary, next_zoom = get_new_plot_details(m, point_to_generate)
end

# max zoom level arbitrarily chosen max zoom level based on trial and error
# nil real implies no point was returned because no edge point exists
if next_zoom > 10 ** 14 || next_real == nil
  archive_album(album)
  exit
end

next_point = create_point(next_real, next_imaginary, next_zoom)

point = update_point album, next_point

save_album(album)
