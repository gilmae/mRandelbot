require 'YAML'
require 'JSON'
require 'fileutils'
require 'aws-sdk'
require 'date'
require 'digest/sha1'
require File.expand_path(File.dirname(__FILE__)) + '/mRandelbot'

m = Mrandelbot.new
a = m.create_album

base_path = File.join(m.base_path, a[:album])
Dir.mkdir(base_path)

gradient = m.generate_gradient
a[:gradient] = gradient

# Always print the gradient in case I was doing a test run and the gradient happens to also be awesome - which has happened a lot
p gradient if m.config["mode"] == "DEV"

def add_meta_data filename, exiftool, real, imag, zoom

  `#{exiftool} -gps:GPSLongitude="#{real}" #{filename}`
  `#{exiftool} -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0

  `#{exiftool} -gps:GPSLatitude="#{imag}" #{filename}`
  `#{exiftool} -gps:GPSLatitudeRef="S" file` if imag.to_f < 0

  `#{exiftool} -DigitalZoomRatio="#{zoom}" #{filename}`
  `#{exiftool} exiftool -delete_original! #{filename}`
end

def upload_to_aws filename, access_key, secret_key, region, bucket
  s3_credentials = Aws::Credentials.new(access_key, secret_key)

  s3 = Aws::S3::Resource.new(region: region, credentials: s3_credentials)

  key = filename.split("/").last
  obj = s3.bucket(bucket).object(key)

  obj.upload_file(filename, {:acl=>"public-read"})

  p key
  p "file uploaded"
  key
end

def queue_message key, config, real, imag, zoom, album
  sqs_credentials = Aws::Credentials.new(config["sqs"]["access_key"], config["sqs"]["secret_key"])
  sqs = Aws::SQS::Client.new(region:  config["sqs"]["region"], credentials: sqs_credentials)
  get_queue_response = sqs.get_queue_url(queue_name: config["sqs"]["queue_name"])

  payload = {:key=>key, :real=>real, :imaginary=>imag, :zoom=>zoom, :album=>album}

  sqs.send_message(queue_url: get_queue_response.queue_url, message_body: JSON.dump(payload)) if config["mode"] != "DEV"
end

coords = ["-0.75", "0"]
zoom = 1

coords_regex = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/

(1..m.config["depth"].to_i).each {|i|
  result = `#{m.config["mandelbrot"]} -mode=edge -w=1000 -h=1000 -z=#{zoom} -r=#{coords[0].strip} -i=#{coords[1].strip}`.chomp

  parsed_coords  = result.scan(coords_regex)

  next if !parsed_coords || parsed_coords.size == 0

  coords = parsed_coords[0]
  zoom *= rand() * 4 + 2

  next if zoom < 50

  filename = `#{m.config["mandelbrot"]} -z=#{zoom} -r=#{coords[0].strip} -i=#{coords[1].strip} -c=true -o=#{base_path} -g='#{gradient}'`.chomp
  add_meta_data filename, m.config["exiftool_path"], coords[0], coords[1], zoom
  if m.config["mode"] != "DEV"
    key = upload_to_aws filename, m.config["s3"]["access_key"], m.config["s3"]["secret_key"], m.config["s3"]["region"], m.config["s3"]["bucket_name"]
    queue_message key, m.config, coords[0], coords[1], zoom, a[:album]
  end

  a[:points] << {zoom: zoom, coords: coords, key: key}
}

results_file_path = File.join(base_path, "#{a[:album]}.json")
File.open(results_file_path, 'w') do|f|
  f.write(a.to_json)
end

upload_to_aws results_file_path, m.config["s3"]["access_key"], m.config["s3"]["secret_key"], m.config["s3"]["region"], m.config["s3"]["site_bucket_name"]
