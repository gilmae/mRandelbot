require "yaml"
require "json"
require "fileutils"
require "date"
require "digest/sha1"
require "http"
require "mastodon"
require File.expand_path(File.dirname(__FILE__)) + "/mRandelbot"
require File.expand_path(File.dirname(__FILE__)) + "/albums"
require File.expand_path(File.dirname(__FILE__)) + "/gradient_gen"

include Albums

COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/
PIXEL_COORDS_REGEX = /(\d+),(\d+)/

def publish(filename, point)
  p "Publishing #{filename} to @randommandelbot@botsin.space"
  client = Mastodon::REST::Client.new(base_url: "https://botsin.space", bearer_token: ENV["MASTODON_TOKEN"], timeout: {read:10})
  real, imaginary, zoom = get_point_coordinate_and_zoom(point)

  media = client.upload_media(HTTP::FormData::File.new(filename, { :content_type => "image/jpeg" }),
                              { :description => "A render of the mandelbrot set using randomised colours. The centre point is #{real} + #{imaginary}i and we are zoomed to #{"%.10e" % zoom} magnitude." })

  return if media.nil? || media.id.nil?

  sleep(5)

  toot = client.create_status("#{real} + #{imaginary}i at zoom #{"%.10e" % zoom}.", { :media_ids => [media.id] })
  p "Published as #{toot.url}"
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
publish filename, point_to_generate

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
