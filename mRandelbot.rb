require 'YAML'
require 'date'
require 'JSON'

class Mrandelbot
   attr_accessor :config, :base_path

   def initialize
     self.read_config
     @base_path = config["images"]
   end

   def generate_gradient
      `#{config["gradient"]}`.chomp
   end

   def read_config
     config_file = File.expand_path(File.dirname(__FILE__)) + '/.config'

     if File.exists? config_file
       _config = File.open(config_file, 'r') do|f|
         _config = YAML.load(f.read)
       end

       @config = _config
     end

     if !_config
       p "Missing config file"
       exit
     end
   end

   def create_album
     {run_at: DateTime.now, album: DateTime.now.strftime("%Y%m%d%H%M%S"), points: [], gradient: generate_gradient}
   end

   def get_album
    album_file = File.expand_path(File.dirname(__FILE__)) + '/current.album'
    _album = create_album

    if File.exists? album_file
      _album = File.open(album_file, 'r') do|f|
        _album = JSON.parse(f.read)
      end
    end
    save_album _album
    _album.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    
  end
   
   def save_album runsheet
    album_file = File.expand_path(File.dirname(__FILE__)) + '/current.album'
    File.open(album_file, 'w') do|f|
      f.write(runsheet.to_json)
    end
   end
end
