module Albums
  SAVEPATH = File.expand_path(File.dirname(__FILE__)) + "/"

  def get_active_albums
    Dir.glob("#{SAVEPATH}*.album").map{|f|f.sub(SAVEPATH, "")}
  end

  def get_album id
    album_file = SAVEPATH + id
    
    if File.exists? album_file
      _album = File.open(album_file, 'r') do|f|
        _album = JSON.parse(f.read)
      end
      return _album.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    end
    nil
  end

  def save_album album
    album_file = SAVEPATH + album[:album] + '.album'
    File.open(album_file, 'w') do|f|
      f.write(album.to_json)
    end
    return album[:album] + '.album'
  end

  def archive_album album
    album_file = SAVEPATH + album[:album] + '.album'
    archived_album_file = SAVEPATH + album[:album] + '.album.archived'

    File.rename(album_file, archived_album_file)
    return archived_album_file
  end

  def create_album
    {run_at: DateTime.now, album: DateTime.now.strftime("%Y%m%d%H%M%S"), points: []}
  end
end