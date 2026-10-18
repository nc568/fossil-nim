## Test search, forum, chat

import std/[os, times]
import ../src/fossil/types
import ../src/fossil/storage/sqlite_backend
import ../src/fossil/search/search
import ../src/fossil/forum/forum
import ../src/fossil/chat/chat

echo "=== test_search ==="
let dbPath = "/tmp/test_search.fossil"
if fileExists(dbPath): removeFile(dbPath)
var db = SqliteBackend()
discard db.open(dbPath)
discard db.initSchema()
discard initSearchIndexSqlite(db)

discard db.indexDocumentSqlite("wiki", "wiki-Test", "Test", "hello world bug report", getTime().toUnix())
discard db.indexDocumentSqlite("ticket", "ticket-123", "Bug title", "fix the bug in code", getTime().toUnix())

let opts = SearchOptions(query: "bug", limit: 10, offset: 0, kinds: @[])
let sRes = db.search(opts)
assert sRes.isOk
echo "search OK count=", sRes.value.len
for r in sRes.value:
  echo "  [" & r.kind & "] " & r.title & " snippet=" & r.snippet

db.close()
if fileExists(dbPath): removeFile(dbPath)

echo "=== test_forum ==="
let dbPath2 = "/tmp/test_forum.fossil"
if fileExists(dbPath2): removeFile(dbPath2)
var db2 = SqliteBackend()
discard db2.open(dbPath2)
discard db2.initSchema()
discard initForumSqlite(db2)

let tRes = db2.createThread("Test thread", "First post content", "tester")
assert tRes.isOk
echo "forum create thread OK id=", tRes.value.id

let listRes = db2.listThreads(10)
assert listRes.isOk
echo "forum list OK count=", listRes.value.len

let getRes = db2.getThread(tRes.value.id)
assert getRes.isOk
echo "forum get OK posts=", getRes.value.posts.len

let pRes = db2.createPost(tRes.value.id, "Reply content", "replyuser")
assert pRes.isOk
echo "forum post reply OK id=", pRes.value.id

db2.close()
if fileExists(dbPath2): removeFile(dbPath2)

echo "=== test_chat ==="
let dbPath3 = "/tmp/test_chat.fossil"
if fileExists(dbPath3): removeFile(dbPath3)
var db3 = SqliteBackend()
discard db3.open(dbPath3)
discard db3.initSchema()
discard initChatSqlite(db3)

let mRes = db3.sendMessage("main", "Hello chat", "tester")
assert mRes.isOk
echo "chat send OK id=", mRes.value.id

let listMRes = db3.listMessages("main", 10)
assert listMRes.isOk
echo "chat list OK count=", listMRes.value.len

db3.close()
if fileExists(dbPath3): removeFile(dbPath3)

echo "All search/forum/chat tests passed!"
