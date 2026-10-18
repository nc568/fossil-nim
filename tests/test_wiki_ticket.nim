## Test wiki and ticket real SQL

import std/[os, strutils, times]
import ../src/fossil/types
import ../src/fossil/storage/sqlite_backend
import ../src/fossil/wiki/wiki
import ../src/fossil/ticket/ticket

echo "=== test_wiki ==="
let dbPath = "/tmp/test_wiki.fossil"
if fileExists(dbPath): removeFile(dbPath)
var db = SqliteBackend()
discard db.open(dbPath)
discard db.initSchema()

let page = WikiPage(name: "TestPage", content: "# Test\nHello **world**", mtime: getTime().toUnix(), user: "test", format: "markdown")
let saveRes = db.saveWikiPage(page, "test wiki save")
assert saveRes.isOk, "wiki save failed: " & (if saveRes.isErr: saveRes.error.msg else: "")
echo "wiki save OK rid=", int(saveRes.value)

let listRes = db.listWikiPages()
assert listRes.isOk
echo "wiki list OK: ", listRes.value.join(", ")
assert "TestPage" in listRes.value

let getRes = db.getWikiPage("TestPage")
assert getRes.isOk, "wiki get failed"
echo "wiki get OK: ", getRes.value.name, " len=", getRes.value.content.len
assert getRes.value.content.contains("Hello")

let html = renderWikiPage(getRes.value)
echo "wiki render OK len=", html.len
assert html.contains("<")

db.close()
if fileExists(dbPath): removeFile(dbPath)

echo "=== test_ticket ==="
let dbPath2 = "/tmp/test_ticket.fossil"
if fileExists(dbPath2): removeFile(dbPath2)
var db2 = SqliteBackend()
discard db2.open(dbPath2)
discard db2.initSchema()

let tRes = db2.createTicket("Test bug", "Description **markdown**", "bug", 2)
assert tRes.isOk, "ticket create failed"
echo "ticket create OK id=", tRes.value.id

let listTRes = db2.listTickets()
assert listTRes.isOk
echo "ticket list OK count=", listTRes.value.len

let getTRes = db2.getTicket(tRes.value.id)
assert getTRes.isOk
echo "ticket get OK: ", getTRes.value.title

let cRes = db2.addComment(tRes.value.id, "First comment **bold**", "tester")
assert cRes.isOk
echo "ticket comment OK id=", cRes.value.id

db2.close()
if fileExists(dbPath2): removeFile(dbPath2)

echo "All wiki/ticket tests passed!"
