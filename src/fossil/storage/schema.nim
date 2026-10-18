## Full Fossil repository and checkout schemas
## Based on fossil's schema.c and checkout.c

const RepoSchema* = """
-- Core artifact storage
CREATE TABLE IF NOT EXISTS blob(
  rid INTEGER PRIMARY KEY,
  rcvid INTEGER,
  size INTEGER,
  uuid TEXT UNIQUE,
  content BLOB,
  CHECK(length(uuid)>=40)
);
CREATE INDEX IF NOT EXISTS blob_uuid ON blob(uuid);
CREATE INDEX IF NOT EXISTS blob_rid ON blob(rid);

-- Delta table: stores delta from src to target
CREATE TABLE IF NOT EXISTS delta(
  rid INTEGER PRIMARY KEY, -- target rid
  srcid INTEGER,           -- source rid
  size INTEGER
);
CREATE INDEX IF NOT EXISTS delta_srcid ON delta(srcid);

-- Config
CREATE TABLE IF NOT EXISTS config(
  name TEXT PRIMARY KEY,
  value TEXT,
  mtime TIMESTAMP,
  user TEXT
);

-- Event timeline
CREATE TABLE IF NOT EXISTS event(
  objid INTEGER PRIMARY KEY,
  type TEXT,
  mtime TIMESTAMP,
  mtime_usec INTEGER,
  user TEXT,
  comment TEXT,
  ecomment TEXT,
  branch TEXT,
  bgColor TEXT,
  eUser TEXT,
  eMtime TIMESTAMP
);
CREATE INDEX IF NOT EXISTS event_mtime ON event(mtime DESC);
CREATE INDEX IF NOT EXISTS event_type ON event(type);
CREATE INDEX IF NOT EXISTS event_branch ON event(branch);

-- Filename
CREATE TABLE IF NOT EXISTS filename(
  fnid INTEGER PRIMARY KEY,
  name TEXT UNIQUE,
  mhash TEXT
);
CREATE INDEX IF NOT EXISTS filename_name ON filename(name);

-- Manifest link: which files in which manifest
CREATE TABLE IF NOT EXISTS mlink(
  mid INTEGER, -- manifest rid
  fid INTEGER, -- file content rid
  fnid INTEGER, -- filename id
  pid INTEGER DEFAULT 0, -- parent file rid for rename tracking?
  mperm INTEGER DEFAULT 0,
  PRIMARY KEY(mid, fnid)
);
CREATE INDEX IF NOT EXISTS mlink_mid ON mlink(mid);
CREATE INDEX IF NOT EXISTS mlink_fid ON mlink(fid);
CREATE INDEX IF NOT EXISTS mlink_fnid ON mlink(fnid);

-- Tags
CREATE TABLE IF NOT EXISTS tag(
  tagid INTEGER PRIMARY KEY,
  tagname TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS tag_tagname ON tag(tagname);

CREATE TABLE IF NOT EXISTS tagxref(
  tagid INTEGER,
  tagtype INTEGER,
  srcid INTEGER,
  origid INTEGER,
  value TEXT,
  mtime TIMESTAMP,
  rid INTEGER,
  PRIMARY KEY(tagid, rid, tagtype)
);
CREATE INDEX IF NOT EXISTS tagxref_tagid ON tagxref(tagid);
CREATE INDEX IF NOT EXISTS tagxref_rid ON tagxref(rid);
CREATE INDEX IF NOT EXISTS tagxref_mtime ON tagxref(mtime);

-- User
CREATE TABLE IF NOT EXISTS user(
  uid INTEGER PRIMARY KEY,
  login TEXT UNIQUE,
  pw TEXT,
  cap TEXT,
  cookie TEXT,
  ipaddr TEXT,
  cexpire TIMESTAMP,
  info TEXT,
  mtime TIMESTAMP
);

-- Private artifacts
CREATE TABLE IF NOT EXISTS private(
  rid INTEGER PRIMARY KEY
);

-- Shun
CREATE TABLE IF NOT EXISTS shun(
  uuid TEXT PRIMARY KEY,
  mtime TIMESTAMP,
  comment TEXT
);

-- Backlink
CREATE TABLE IF NOT EXISTS backlink(
  target TEXT,
  src TEXT,
  mtime TIMESTAMP
);

-- Unclustered
CREATE TABLE IF NOT EXISTS unclustered(
  rid INTEGER PRIMARY KEY
);

-- Audit
CREATE TABLE IF NOT EXISTS audit(
  auditid INTEGER PRIMARY KEY,
  atime TIMESTAMP,
  login TEXT,
  ipaddr TEXT,
  action TEXT
);

-- Ticket
CREATE TABLE IF NOT EXISTS ticket(
  tkt_id INTEGER PRIMARY KEY,
  tkt_uuid TEXT UNIQUE,
  tkt_title TEXT,
  tkt_desc TEXT,
  tkt_status TEXT,
  tkt_type TEXT,
  tkt_priority INTEGER,
  tkt_owner TEXT,
  tkt_reporter TEXT,
  tkt_ctime INTEGER,
  tkt_mtime INTEGER
);
CREATE INDEX IF NOT EXISTS ticket_uuid ON ticket(tkt_uuid);
CREATE INDEX IF NOT EXISTS ticket_status ON ticket(tkt_status);

CREATE TABLE IF NOT EXISTS ticketchng(
  tkt_id TEXT,
  tkt_rid INTEGER,
  tkt_mtime INTEGER,
  login TEXT,
  tkt_comment TEXT
);
CREATE INDEX IF NOT EXISTS ticketchng_tkt_id ON ticketchng(tkt_id);

-- Forum - full schema with moderation fields (must match forum/forum.nim)
CREATE TABLE IF NOT EXISTS forum_thread(
  thread_id TEXT PRIMARY KEY,
  title TEXT,
  user TEXT,
  created INTEGER,
  last_mtime INTEGER,
  pinned INTEGER DEFAULT 0,
  locked INTEGER DEFAULT 0,
  deleted INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS forum_post(
  post_id TEXT PRIMARY KEY,
  thread_id TEXT,
  parent_id TEXT,
  user TEXT,
  mtime INTEGER,
  title TEXT,
  content TEXT,
  uuid TEXT,
  rid INTEGER,
  edited INTEGER DEFAULT 0,
  deleted INTEGER DEFAULT 0,
  attachment TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS forum_post_thread ON forum_post(thread_id);
CREATE TABLE IF NOT EXISTS forum_moderation(
  queue_id TEXT PRIMARY KEY,
  post_id TEXT,
  thread_id TEXT,
  user TEXT,
  mtime INTEGER,
  reason TEXT,
  status TEXT DEFAULT 'pending'
);

-- Chat - full schema with attachments
CREATE TABLE IF NOT EXISTS chat_message(
  msg_id TEXT PRIMARY KEY,
  room TEXT,
  user TEXT,
  mtime INTEGER,
  content TEXT,
  uuid TEXT,
  rid INTEGER,
  attachment TEXT DEFAULT '',
  edited INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_chat_message_room ON chat_message(room);
CREATE TABLE IF NOT EXISTS chat_room(
  room TEXT PRIMARY KEY,
  owner TEXT,
  is_private INTEGER DEFAULT 0,
  created INTEGER
);
CREATE TABLE IF NOT EXISTS chat_presence(
  user TEXT,
  room TEXT,
  last_seen INTEGER,
  typing INTEGER DEFAULT 0,
  status TEXT DEFAULT 'online',
  PRIMARY KEY(user, room)
);

-- Search FTS5
CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61');
CREATE TABLE IF NOT EXISTS search_index(
  id TEXT PRIMARY KEY,
  kind TEXT,
  title TEXT,
  content TEXT,
  mtime INTEGER
);
"""

const CheckoutSchema* = """
-- Checkout database (_FOSSIL_ or .fslckout)

-- Variables
CREATE TABLE IF NOT EXISTS vvar(
  name TEXT PRIMARY KEY,
  value TEXT
);

-- Vfile: working tree state
CREATE TABLE IF NOT EXISTS vfile(
  id INTEGER PRIMARY KEY,
  pathname TEXT UNIQUE,
  deleted BOOLEAN DEFAULT 0,
  isexe BOOLEAN DEFAULT 0,
  islink BOOLEAN DEFAULT 0,
  rid INTEGER DEFAULT 0, -- rid of file content in repo
  mrid INTEGER DEFAULT 0, -- rid of file content in manifest?
  chnged BOOLEAN DEFAULT 0,
  mtime INTEGER DEFAULT 0,
  origname TEXT
);
CREATE INDEX IF NOT EXISTS vfile_pathname ON vfile(pathname);
CREATE INDEX IF NOT EXISTS vfile_rid ON vfile(rid);

-- Vmerge: merge state
CREATE TABLE IF NOT EXISTS vmerge(
  id INTEGER PRIMARY KEY,
  mergeid INTEGER,
  rid INTEGER,
  fnid INTEGER
);

-- Undo
CREATE TABLE IF NOT EXISTS undo(
  id INTEGER PRIMARY KEY,
  op TEXT,
  arg1 TEXT,
  arg2 TEXT,
  arg3 TEXT,
  arg4 TEXT
);

-- Stash (localdb)
CREATE TABLE IF NOT EXISTS stash(
  stashid INTEGER PRIMARY KEY,
  vid INTEGER,
  comment TEXT,
  ctime TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stashfile(
  stashid INTEGER REFERENCES stash,
  rid INTEGER,
  isAdded BOOLEAN,
  isRemoved BOOLEAN,
  isExec BOOLEAN,
  isLink BOOLEAN,
  origname TEXT,
  newname TEXT,
  delta BLOB,
  PRIMARY KEY(newname, stashid)
);

-- Local config
CREATE TABLE IF NOT EXISTS local_config(
  name TEXT PRIMARY KEY,
  value TEXT
);
"""

const FullSchema* = RepoSchema & "\n" & CheckoutSchema
