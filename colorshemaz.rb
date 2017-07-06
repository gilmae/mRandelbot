require 'rmagick'
require 'twitter'

config_file = File.expand_path(File.dirname(__FILE__)) + '/.config'

if File.exists? config_file
  config = File.open(config_file, 'r') do|f|
    config = YAML.load(f.read)
  end
end

if !config
  p "Missing config file"
  exit
end

client = Twitter::REST::Client.new do |twitter|
   twitter.consumer_key = config["twitter"]["CONSUMER_KEY"]
   twitter.consumer_secret = config["twitter"]["CONSUMER_SECRET"]
   twitter.access_token = config["twitter"]["OAUTH_TOKEN"]
   twitter.access_token_secret = config["twitter"]["OAUTH_TOKEN_SECRET"]
 end

# Get most recent tweet
client.user_timeline("colorschemez").first.id

# Get media and download

# build gradient from the image

# generate plot

# tweet

def get_rgb pixel
   return "#{to_hex(pixel.red)}#{to_hex(pixel.green)}#{to_hex(pixel.blue)}"
end

def to_hex i
   return (i/256).to_s(16).rjust(2, "0")
end
img = Magick::ImageList.new(ARGV[0]).first

first_row = img.get_pixels(0,0,img.columns,1)
first_col = img.get_pixels(0,0,1,img.rows)

pixels = first_row
dimension = img.columns
if first_col.uniq.length > 1
  pixels = first_col
  dimension = img.rows
end

dimension = dimension.to_f
last = ""

stops = []
pixels.each.with_index do |pixel,i|
   rgb = get_rgb pixel
   if rgb != last
     last=rgb
     stops << [(i/dimension).to_s,rgb]
   end
end

p stops
