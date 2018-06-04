require "sqlite3"
module Albums
  SAVEPATH = "/mb/mRandelbot.db"
  INIT_ALBUMS = "create table albums (name varchar(40), run_at datetime, gradient varchar(2000), archived bool); "
  INIT_POINTS = "create table points (zoom float,real float,imag float,published bool,generatedAt datetime,createdAt datetime,albumId int);"

  INSERT_ALBUM = "insert into albums (name, run_at, gradient, archived) values (?, ?, ?, ?)"
  UPDATE_ALBUM = "update albums set name=?, run_at=?, gradient=?, archived=? where rowid = ?"

  INSERT_POINT = "insert into points (zoom,real,imag,generatedAt,createdAt,albumId) values (?,?,?,?,?,?)"
  UPDATE_POINT = "update points set zoom = ?,real = ?,imag = ?,generatedAt = ?,createdAt = ?,albumId = ? where rowid = ?"
  
  def get_db
    requires_init = !File.exists?(SAVEPATH)
    db = SQLite3::Database.new SAVEPATH
    if requires_init
      db.execute INIT_ALBUMS
      db.execute INIT_POINTS
    end

    db
  end

  def get_active_albums
    #Dir.glob("#{SAVEPATH}*.album").map{|f|f.sub(SAVEPATH, "")}
    db = get_db()
    db.results_as_hash = true
    db.execute("select rowid,name,gradient,archived,run_at from albums where archived = 0")

  end

  def get_album id
    db = get_db()
    db.results_as_hash = true

    db.execute("select rowid,name,gradient,archived,run_at from albums where rowid = ?", [id])[0]
  end

  def save_album album
     if album["rowid"]
      get_db().execute(UPDATE_ALBUM, album["name"], album["run_at"], album["gradient"], album["archived"], album["rowid"])
      get_album album["rowid"]
     else
      db = get_db()
      vars =  [album["name"], album["run_at"], album["gradient"].to_json, album["archived"]]

      db.execute(INSERT_ALBUM, vars)
      get_album db.last_insert_row_id()
    end
  end

  def archive_album album
    album["archived"] = true
    save_album album
  end

  def create_album
    {"run_at"=> DateTime.now.strftime("%Y-%m-%dT%H:%M:%S"), 
      "name"=> DateTime.now.strftime("%Y%m%d%H%M%S"),
      "archived"=>0,
      "gradient"=>""
    }
  end

  def get_point id
    db = get_db()
    db.results_as_hash = true
    db.execute("select rowid,zoom,real,imag,published,generatedAt,createdAt,albumId from points where rowid = ?", id)
  end

  def update_point album, point
    point["albumId"] = album["rowid"]
    if point["rowid"]
      vars = [point["zoom"],point["real"],point["imag"],point["generatedAt"],point["createdAt"],point["albumId"], point["rowid"]]
      get_db().execute(UPDATE_POINT,vars)
      return get_point point["rowid"]
    else
      db = get_db()
      db.execute(INSERT_POINT, point["zoom"],point["real"],point["imag"],point["generatedAt"],point["createdAt"],point["albumId"])
      get_point db.last_insert_row_id()
    end
  end

  def get_next_point album
    db = get_db()
    db.results_as_hash = true
    db.execute("select rowid,zoom,real,imag,published,generatedAt,createdAt,albumId from points where albumId=? and generatedat = ''", album["rowid"])
  end
end