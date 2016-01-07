require 'twitter'
require 'YAML'
require 'fileutils'

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

mb_file_regex = /mb_([^_]+)_([^_]+)_([^_]+)\./

next_mb = Dir.entries(base_path).sort_by { |a| File.mtime(base_path + a) }.find do |a|
  mb_file_regex =~ a;
end

exit if next_mb.nil?

m = next_mb.match(mb_file_regex)

real = m.captures[0]
imaginary = m.captures[1]
zoom = m.captures[2]


if !config["twitter"]
  p "Twitter configuration missing"
  exit
end

# configure up the external services
client = Twitter::REST::Client.new do |twitter|
    twitter.consumer_key = config["twitter"]["CONSUMER_KEY"]
    twitter.consumer_secret = config["twitter"]["CONSUMER_SECRET"]
    twitter.access_token = config["twitter"]["OAUTH_TOKEN"]
    twitter.access_token_secret = config["twitter"]["OAUTH_TOKEN_SECRET"]
  end

"Snapshot taken#{real} + #{imaginary}i at zoom #{zoom}"

File.open(base_path + next_mb, "r") do |file|
   client.update_with_media("#{real} + #{imaginary}i at zoom #{zoom}", file, {:lat=>imaginary, :long=>real, :display_coordinates=>'true'})
end

FileUtils.mv(base_path + next_mb, base_path + "posted/" + next_mb)
