import db_sqlite

const dbfile {.strdefine.}: string = "db.sqlite"
echo dbfile
let db* = open(dbfile, nil, nil, nil)