require 'YAML'
require 'JSON'
require 'fileutils'
require 'aws-sdk'
require 'date'
require 'digest/sha1'


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

base_path = config["images"]

base_path = File.join(base_path, DateTime.now.strftime("%Y%m%d%H%M%S"))
Dir.mkdir(base_path)

run_details = {}
run_details["Date Ran"] = DateTime.now

gradient = `#{config["gradient"]}`.chomp

# Always print the gradient in case I was doing a test run and the gradient happens to also be awesome - which has happened a lot
p gradient

run_details[:gradient] = gradient
album = Digest::SHA1.base64digest(gradient)

def add_meta_data filename, config, real, imag, zoom
  exiftool_location = config["exiftool_path"]
  `#{exiftool_location} -gps:GPSLongitude="#{real}" #{filename}`
  `#{exiftool_location} -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0

  `#{exiftool_location} -gps:GPSLatitude="#{imag}" #{filename}`
  `#{exiftool_location} -gps:GPSLatitudeRef="S" file` if imag.to_f < 0

  `#{exiftool_location} -DigitalZoomRatio="#{zoom}" #{filename}`
  `#{exiftool_location} exiftool -delete_original! #{filename}`
end

def upload_to_aws filename, config, real, imag, zoom, album
  sqs_credentials = Aws::Credentials.new(config["sqs"]["access_key"], config["sqs"]["secret_key"])
  s3_credentials = Aws::Credentials.new(config["s3"]["access_key"], config["s3"]["secret_key"])

  sqs = Aws::SQS::Client.new(region:  config["sqs"]["region"], credentials: sqs_credentials)

  s3 = Aws::S3::Resource.new(region: config["s3"]["region"], credentials: s3_credentials)

  get_queue_response = sqs.get_queue_url(queue_name: config["sqs"]["queue_name"])

  key = filename.split("/").last
  obj = s3.bucket(config["s3"]["bucket_name"]).object(key)

  obj.upload_file(filename) if config["mode"] != "DEV"

  payload = {:key=>key, :real=>real, :imaginary=>imag, :zoom=>zoom, :album=>album}

  sqs.send_message(queue_url: get_queue_response.queue_url, message_body: JSON.dump(payload)) if config["mode"] != "DEV"

  p JSON.dump(payload) if config["mode"] == "DEV"
end

coords = ["-0.75", "0"]
zoom = 1

coords_regex = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/

run_details["points"] = []
(1..20).each {|i|

  run_details["points"] << {zoom: zoom, coords: coords}

  result = `#{config["mandelbrot"]} -mode=edge -w=1000 -h=1000 -z=#{zoom} -r=#{coords[0].strip} -i=#{coords[1].strip}`.chomp

  parsed_coords  = result.scan(coords_regex)

  next if !parsed_coords || parsed_coords.size == 0

  coords = parsed_coords[0]
  zoom *= rand() * 4 + 2

  next if zoom < 50

  filename = `#{config["mandelbrot"]} -z=#{zoom} -r=#{coords[0].strip} -i=#{coords[1].strip} -c=true -o=#{base_path} -g='#{gradient}'`.chomp

  add_meta_data filename, config, coords[0], coords[1], zoom
  upload_to_aws filename, config, coords[0], coords[1], zoom, album

}

File.open(File.join(base_path, "run_details.json"), 'w') do|f|
  f.write(run_details.to_json)
end
