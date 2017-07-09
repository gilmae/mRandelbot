require 'YAML'
require 'date'

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
     {run_at: DateTime.now, album: DateTime.now.strftime("%Y%m%d%H%M%S"), points: []}
   end
end
