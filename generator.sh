#!/usr/bin/ruby

require 'YAML'
require 'JSON'
require 'fileutils'
require 'aws-sdk'


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

real = rand() * 3.7 - 2.6
imag = rand() * 2.4 - 1.1
zoom = rand() * 2**10 + 1

filename = `#{config["mandelbrot"]} -r=#{real} -i=#{imag} -z=#{zoom} -c=smooth -o=#{base_path}`

filename.chomp!
#p filename

identify_location = `brew --prefix imagemagick`.chomp!
result = `#{identify_location}/bin/identify -verbose #{filename}`

g = result.scan(/standard deviation: (([3-9]\d)|(25)|([1-2]\d\d))/)

if g.size < 2
  `rm #{filename}`
else
  exiftool_location = `brew --prefix exiftool`.chomp!
  `#{exiftool_location}/bin/exiftool -gps:GPSLongitude="#{real}" #{filename}`
  `#{exiftool_location}/bin/exiftool -gps:GPSLongitudeRef="W" #{filename}` if real < 0

  `#{exiftool_location}/bin/exiftool -gps:GPSLatitude="#{imag}" #{filename}`
  `#{exiftool_location}/bin/exiftool -gps:GPSLatitudeRef="S" file` if imag < 0

  `#{exiftool_location}/bin/exiftool -DigitalZoomRatio="#{zoom}" #{filename}`
  `#{exiftool_location}/bin/exiftool exiftool -delete_original! #{filename}`

  sqs_credentials = Aws::Credentials.new(config["sqs"]["access_key"], config["sqs"]["secret_key"])
  s3_credentials = Aws::Credentials.new(config["s3"]["access_key"], config["s3"]["secret_key"])

  sqs = Aws::SQS::Client.new(region:  config["sqs"]["region"], credentials: sqs_credentials)

  s3 = Aws::S3::Resource.new(region: config["s3"]["region"], credentials: s3_credentials)

  get_queue_response = sqs.get_queue_url(queue_name: config["sqs"]["queue_name"])

  key = filename.split("/").last
  obj = s3.bucket(config["s3"]["bucket_name"]).object(key)
  obj.upload_file(filename)

  payload = {:key=>key, :real=>real, :imaginary=>imag, :zoom=>zoom}

  sqs.send_message(queue_url: get_queue_response.queue_url, message_body: JSON.dump(payload))
end
