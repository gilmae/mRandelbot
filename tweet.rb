require 'twitter'
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

# the files we are interested in are in th format:
#   mb_real_imaginary_zoom.[png/jpg]

#mb_file_regex = /mb_([^_]+)_([^_]+)_([^_]+)\./

#next_mb = Dir.entries(base_path).sort_by { |a| File.mtime(base_path + a) }.find do |a|
#  mb_file_regex =~ a;
#end

#exit if next_mb.nil?

#m = next_mb.match(mb_file_regex)

#real = m.captures[0]
#imaginary = m.captures[1]
#zoom = m.captures[2]


if !config["twitter"]
  p "Twitter configuration missing"
  exit
end

if !config["sqs"]
  p "AWS SQS configuration missing"
  exit
end

if !config["s3"]
  p "AWS S3 configuration missing"
  exit
end

sqs_credentials = Aws::Credentials.new(config["sqs"]["access_key"], config["sqs"]["secret_key"])
s3_credentials = Aws::Credentials.new(config["s3"]["access_key"], config["s3"]["secret_key"])

sqs = Aws::SQS::Client.new(region:  config["sqs"]["region"], credentials: sqs_credentials)

s3 = Aws::S3::Resource.new(region: config["s3"]["region"], credentials: s3_credentials)

get_queue_response = sqs.get_queue_url(queue_name: config["sqs"]["queue_name"])

receive_resp = sqs.receive_message({queue_url: get_queue_response.queue_url, max_number_of_messages: 1})

exit if (receive_resp.nil? || receive_resp.messages.nil? || receive_resp.messages.size == 0)

msg = receive_resp.messages.first

payload = JSON.load(msg.body)

key = payload["key"]
filepath = '/tmp/#{key}'

bucket = s3.bucket(config["s3"]["bucket_name"])
obj = bucket.object(key)
obj.get({response_target: filepath})

#configure up the external services
client = Twitter::REST::Client.new do |twitter|
   twitter.consumer_key = config["twitter"]["CONSUMER_KEY"]
   twitter.consumer_secret = config["twitter"]["CONSUMER_SECRET"]
   twitter.access_token = config["twitter"]["OAUTH_TOKEN"]
   twitter.access_token_secret = config["twitter"]["OAUTH_TOKEN_SECRET"]
 end

File.open(filepath, "r") do |file|
  client.update_with_media("#{payload["real"]} + #{payload["imaginary"]}i at zoom #{payload["zoom"]}", file, {:lat=>payload["imaginary"], :long=>payload["real"], :display_coordinates=>'true'})
end

FileUtils.rm(filepath)

new_key = "#{config["s3"]["posted_folder"]}/#{key}"
obj.move_to(bucket.object(new_key))

resp = sqs.delete_message({
  queue_url: get_queue_response.queue_url,
  receipt_handle: msg.receipt_handle
})
