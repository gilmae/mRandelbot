require "yaml"
require "date"
require "json"

class Mrandelbot
  attr_accessor :config, :base_path

  def base_path
    ENV["MRANDELBOT_IMAGES_PATH"]
  end
end

def generate_image(m, next_point, album)
  album_base_path = get_album_base_path(m, album)
  maxIterations = get_max_iterations(next_point["zoom"])
  p "Generate plot at #{next_point["real"]} + #{next_point["imag"]}, zoomed in to #{next_point["zoom"]}, with max iterations of #{maxIterations}, in #{album_base_path}"
  `mandelbrot -z=#{next_point["zoom"]} -r=#{next_point["real"]} -i=#{next_point["imag"]} -c=true -o=#{album_base_path} -g='#{album["gradient"]}' -m=#{maxIterations}`.chomp
end

def seed_points_up_to(m, seed_until)
  r = -0.75
  i = 0.000000001
  z = 1

  r, i = get_a_point m, -0.75, 0, 1

  z *= seed_until + rand() * 4 + 2

  return r, i, z
end

def get_a_point(m, real, imaginary, zoom)
  maxIterations = get_max_iterations(zoom)
  puts "mandelbrot -o=#{m.base_path} -f=tmp.jpg -z=#{zoom} -r=#{real} -i=#{imaginary} -m=#{maxIterations}"
  result = `mandelbrot -o=#{m.base_path} -f=tmp.jpg -z=#{zoom} -r=#{real} -i=#{imaginary} -m=#{maxIterations}`.chomp
  pixels = `convert #{result} -canny 0x1+10%+30% -write TXT:- | grep "#FFF" | shuf -n 1 | awk -F':' '{print $1}'`.chomp

  if PIXEL_COORDS_REGEX.match(pixels)
    parsed_pixels = pixels.scan(PIXEL_COORDS_REGEX)[0]
    coords = `mandelbrot -mode=coordsAt -z=#{zoom} -r=#{real} -i=#{imaginary} -x=#{parsed_pixels[0]} -y=#{parsed_pixels[1]} `.chomp
    if COORDS_REGEX.match(coords)
      parsed_coords = coords.scan(COORDS_REGEX)[0]
      return parsed_coords[0], parsed_coords[1]
    end
  end

  return nil, nil
end

def add_meta_data(filename, point)
  real, imaginary, zoom = get_point_coordinate_and_zoom(point)

  `exiftool -gps:GPSLongitude="#{real}" #{filename}`
  `exiftool -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0

  `exiftool -gps:GPSLatitude="#{imaginary}" #{filename}`
  `exiftool -gps:GPSLatitudeRef="S" file` if imaginary.to_f < 0

  `exiftool -DigitalZoomRatio="#{zoom}" #{filename}`
  `exiftool exiftool -delete_original! #{filename}`
end

def get_album_base_path(m, album)
  album_base_path = File.join(m.base_path, album["name"])
  Dir.mkdir(album_base_path) if !Dir.exists?(album_base_path)
  album_base_path
end

def create_a_new_album(m)
  a = create_album
  album_base_path = get_album_base_path(m, a)
  Dir.mkdir(album_base_path) if !Dir.exists?(album_base_path)
  a["gradient"] = generate_gradient
  #a[:gradient] = m.generate_gradient#generate_gradient
  save_album a
end

def create_point(real, imaginary, zoom)
  return { "id" => rand(), "zoom" => zoom, "real" => real, "imag" => imaginary, "published" => false, "generatedAt" => "", "createdAt" => DateTime.now.strftime("%Y-%m-%dT%H:%M:%S") }
end

def get_an_album(m)
  active_albums = get_active_albums

  puts "There are #{active_albums.size} active albums"

  # To keep things interesting, we pick an album at random.
  # To ensure we don't always just have one album, we also allow
  # for two extra slots, and if one of those slots is chosen, we
  # create a new album
  album_to_use = (rand() * (active_albums.size + 2)).to_i

  if (album_to_use >= active_albums.size)
    new_album = create_a_new_album(m)
    puts "Creating a new album - #{new_album["name"]}"
    return new_album
  end

  album = get_album(active_albums[album_to_use]["rowid"])
  puts "Using existing album - #{album["name"]}"

  return album
end

def get_new_plot_details(m, last_plot)
  real, imaginary, zoom = nil
  if !last_plot
    real, imaginary, zoom = seed_points_up_to m, 50
  else
    r, i, z = get_point_coordinate_and_zoom last_plot

    real, imaginary = get_a_point m, r, i, z
    zoom = z.to_f * (rand() * 4 + 2)
  end

  return real, imaginary, zoom
end

def get_point_coordinate_and_zoom(point)
  real = point["real"]
  imaginary = point["imag"]
  zoom = point["zoom"]

  return real, imaginary, zoom
end

def get_max_iterations(zoom)
  2000 + 50 * [0.0, Math.log(zoom, 10)].max.to_i
end
