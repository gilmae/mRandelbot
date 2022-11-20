require "yaml"
require "json"
require "fileutils"
require "date"
require "digest/sha1"
require "http"
require File.expand_path(File.dirname(__FILE__)) + "/mRandelbot"
require File.expand_path(File.dirname(__FILE__)) + "/albums"
require File.expand_path(File.dirname(__FILE__)) + "/gradient_gen"

include Albums

COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/
PIXEL_COORDS_REGEX = /(\d+),(\d+)/

def publish(filename, point)
  p "Publishing #{filename} to micropub"

  ctx = OpenSSL::SSL::SSLContext.new
  if ENV["DISTRUST_MICROPUB_SSL"]
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  r = HTTP.auth("Bearer #{ENV["MICROPUB_KEY"]}").post(ENV["MICROPUB_MEDIA"], :ssl_context => ctx, :form => {
                                                                               :file => HTTP::FormData::File.new(filename, { :content_type => "image/jpeg" }),
                                                                             })

  return unless r.status == 201
  fileLocation = r["Location"]

  real, imaginary, zoom = get_point_coordinate_and_zoom(point)
  r = HTTP.auth("Bearer #{ENV["MICROPUB_KEY"]}").post(ENV["MICROPUB_PUBLISH"], :ssl_context => ctx, :json => {
                                                                                 :type => [
                                                                                   "h-entry",
                                                                                 ],
                                                                                 :properties => {
                                                                                   :content => [
                                                                                     "#{real} + #{imaginary}i at zoom #{"%.10e" % zoom}.",
                                                                                   ],
                                                                                   "post-status" => ["published"],
                                                                                   :photo => [
                                                                                     {
                                                                                       :value => fileLocation,
                                                                                       :alt => "A render of the Mandelbrot Set at #{real} + #{imaginary}i at zoom #{"%.10e" % zoom}",
                                                                                     },
                                                                                   ],
                                                                                   "mp-syndicate-to": (ENV["MICROPUB_SYNDICATE_TO"] || "").split(","),
                                                                                 },
                                                                               })
  p "Published as #{r["Location"]}"
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
