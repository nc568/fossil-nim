## MCP Tools definitions — Effective MCP Design
## Based on research: 5 mistakes, outcome-oriented, annotations, progressive disclosure, token budget

import std/[json, tables, options, strutils]

type
  McpToolAnnotation* = object
    title*: string
    readOnlyHint*: bool
    destructiveHint*: bool
    idempotentHint*: bool
    openWorldHint*: bool

  McpTool* = object
    name*: string
    description*: string
    inputSchema*: JsonNode
    annotations*: McpToolAnnotation

  McpToolHandler* = proc(args: JsonNode): JsonNode {.gcsafe.}

  McpToolRegistry* = object
    tools*: Table[string, tuple[def: McpTool, handler: McpToolHandler]]

proc newRegistry*(): McpToolRegistry = McpToolRegistry(tools: initTable[string, tuple[def: McpTool, handler: McpToolHandler]]())

proc registerTool*(reg: var McpToolRegistry, name: string, desc: string, schema: JsonNode, handler: McpToolHandler, annot: McpToolAnnotation) =
  reg.tools[name] = (def: McpTool(name: name, description: desc, inputSchema: schema, annotations: annot), handler: handler)

proc listTools*(reg: McpToolRegistry): JsonNode =
  var arr = newJArray()
  for _, (def, _) in reg.tools:
    var obj = newJObject()
    obj["name"] = newJString(def.name)
    obj["description"] = newJString(def.description)
    obj["inputSchema"] = def.inputSchema
    var ann = newJObject()
    ann["title"] = newJString(def.annotations.title)
    ann["readOnlyHint"] = newJBool(def.annotations.readOnlyHint)
    ann["destructiveHint"] = newJBool(def.annotations.destructiveHint)
    ann["idempotentHint"] = newJBool(def.annotations.idempotentHint)
    ann["openWorldHint"] = newJBool(def.annotations.openWorldHint)
    obj["annotations"] = ann
    arr.add obj
  var resultObj = newJObject()
  resultObj["tools"] = arr
  resultObj

proc searchTools*(reg: McpToolRegistry, query: string): JsonNode =
  ## Progressive disclosure: search tools by query, return only relevant
  var arr = newJArray()
  let q = query.toLowerAscii()
  for _, (def, _) in reg.tools:
    if q.len==0 or def.name.toLowerAscii().contains(q) or def.description.toLowerAscii().contains(q):
      var obj = newJObject()
      obj["name"] = newJString(def.name)
      obj["description"] = newJString(def.description)
      obj["inputSchema"] = def.inputSchema
      var ann = newJObject()
      ann["title"] = newJString(def.annotations.title)
      ann["readOnlyHint"] = newJBool(def.annotations.readOnlyHint)
      ann["destructiveHint"] = newJBool(def.annotations.destructiveHint)
      ann["idempotentHint"] = newJBool(def.annotations.idempotentHint)
      ann["openWorldHint"] = newJBool(def.annotations.openWorldHint)
      obj["annotations"] = ann
      arr.add obj
  var resultObj = newJObject()
  resultObj["tools"] = arr
  resultObj["query"] = newJString(query)
  resultObj["count"] = newJInt(arr.len)
  resultObj

# --- Annotations helpers ---
proc roAnnot(title: string): McpToolAnnotation = McpToolAnnotation(title: title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
proc rwAnnot(title: string, destructive=false, idempotent=false, openWorld=false): McpToolAnnotation = McpToolAnnotation(title: title, readOnlyHint: false, destructiveHint: destructive, idempotentHint: idempotent, openWorldHint: openWorld)
proc roOpenAnnot(title: string): McpToolAnnotation = McpToolAnnotation(title: title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true)

# --- Schemas with detailed descriptions (AI reads these at call time) ---
let emptySchema = parseJson("""{"type":"object","properties":{}}""")

let statusSchema = parseJson("""{
  "type":"object",
  "properties":{
    "repoPath":{"type":"string","description":"Path to repo file (e.g. /tmp/repo.fossil) or checkout dir, optional — auto-detected via _FOSSIL_ or env FOSSIL_REPO if omitted"}
  },
  "additionalProperties": false
}""")

let diffSchema = parseJson("""{
  "type":"object",
  "properties":{
    "file":{"type":"string","description":"Specific file path relative to checkout root, e.g. src/main.nim — if omitted, shows diff for all changed files"},
    "rev1":{"type":"string","description":"First revision (rid, uuid prefix, or branch name), default HEAD / trunk tip"},
    "rev2":{"type":"string","description":"Second revision, default working tree (uncommitted changes)"},
    "context":{"type":"integer","description":"Number of context lines for unified diff, default 3","default":3}
  },
  "additionalProperties": false
}""")

let commitSchema = parseJson("""{
  "type":"object",
  "properties":{
    "message":{"type":"string","description":"Commit message — first line 50 chars max imperative mood, e.g. 'Fix login bypass', then blank line and body"},
    "files":{"type":"array","items":{"type":"string"},"description":"Files to commit relative to checkout root, e.g. ['src/foo.nim'], empty = all changed files"},
    "branch":{"type":"string","description":"Branch name, default trunk, e.g. 'feature-x'"},
    "user":{"type":"string","description":"Committer name, default $USER env"},
    "idempotencyKey":{"type":"string","description":"Idempotency key to prevent duplicate commits on retry — use UUID, e.g. '550e8400-e29b-41d4-a716-446655440000'. If same key used twice, second call returns cached result without creating new commit"}
  },
  "required":["message"],
  "additionalProperties": false
}""")

let smartCommitSchema = parseJson("""{
  "type":"object",
  "properties":{
    "branch":{"type":"string","description":"Branch name, default trunk"},
    "user":{"type":"string","description":"Committer, default env USER"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate commits"},
    "autoAdd":{"type":"boolean","description":"Auto-add untracked files that look like source code, default false","default":false}
  },
  "additionalProperties": false
}""")

let logSchema = parseJson("""{
  "type":"object",
  "properties":{
    "file":{"type":"string","description":"File path to get history for, e.g. src/fossil/api/rest.nim"},
    "limit":{"type":"integer","description":"Max number of history entries, default 20, max 100","default":20,"minimum":1,"maximum":100}
  },
  "required":["file"],
  "additionalProperties": false
}""")

let timelineSchema = parseJson("""{
  "type":"object",
  "properties":{
    "limit":{"type":"integer","description":"Max checkins, default 20, max 100","default":20,"minimum":1,"maximum":100},
    "branch":{"type":"string","description":"Filter by branch name, e.g. trunk, feature-x"},
    "user":{"type":"string","description":"Filter by committer username"},
    "since":{"type":"string","description":"ISO date since filter, e.g. 2024-01-01"},
    "format":{"type":"string","description":"Output format: text (human readable) or json (structured)","enum":["text","json"],"default":"text"}
  },
  "additionalProperties": false
}""")

let fileContentSchema = parseJson("""{
  "type":"object",
  "properties":{
    "path":{"type":"string","description":"File path relative to checkout or repo, e.g. README.md, src/main.nim — must be inside checkout (path traversal blocked)"},
    "rev":{"type":"string","description":"Revision rid, uuid, or branch, default HEAD / working tree","default":"HEAD"},
    "maxBytes":{"type":"integer","description":"Max bytes to return to stay within context budget, default 8000, max 20000","default":8000,"minimum":100,"maximum":20000}
  },
  "required":["path"],
  "additionalProperties": false
}""")

let fileListSchema = parseJson("""{
  "type":"object",
  "properties":{
    "pattern":{"type":"string","description":"Glob pattern to filter files, e.g. '*.nim', 'src/**/*.nim', optional"},
    "limit":{"type":"integer","description":"Max files, default 100, max 500","default":100,"minimum":1,"maximum":500}
  },
  "additionalProperties": false
}""")

let branchCreateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "name":{"type":"string","description":"New branch name, e.g. feature-x, must be alphanumeric with -_"},
    "from":{"type":"string","description":"Base branch or rid to branch from, default trunk tip"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate branch creation"}
  },
  "required":["name"],
  "additionalProperties": false
}""")

let branchCloseSchema = parseJson("""{
  "type":"object",
  "properties":{
    "name":{"type":"string","description":"Branch name to close, e.g. feature-x"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["name"],
  "additionalProperties": false
}""")

let tagSchema = parseJson("""{
  "type":"object",
  "properties":{
    "name":{"type":"string","description":"Tag name, e.g. v1.0.0"},
    "rid":{"type":"string","description":"Rid or uuid to tag, default HEAD"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["name"],
  "additionalProperties": false
}""")

let blameSchema = parseJson("""{
  "type":"object",
  "properties":{
    "file":{"type":"string","description":"File path to blame, e.g. src/main.nim — must be inside checkout"},
    "limit":{"type":"integer","description":"Max lines, default 100","default":100}
  },
  "required":["file"],
  "additionalProperties": false
}""")

let infoSchema = parseJson("""{
  "type":"object",
  "properties":{
    "rid":{"type":"string","description":"Rid (integer) or uuid (64 hex chars) of artifact to get info for, e.g. 1 or abc123..."},
    "uuid":{"type":"string","description":"Alias for rid, uuid of artifact"}
  },
  "additionalProperties": false
}""")

let mergeSchema = parseJson("""{
  "type":"object",
  "properties":{
    "branch":{"type":"string","description":"Branch to merge into current, e.g. feature-x"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["branch"],
  "additionalProperties": false
}""")

let stashSchema = parseJson("""{
  "type":"object",
  "properties":{
    "message":{"type":"string","description":"Stash message, default WIP"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID for save"}
  },
  "additionalProperties": false
}""")

let stashApplySchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"integer","description":"Stash id to apply, e.g. 1"},
    "drop":{"type":"boolean","description":"Drop stash after apply, default false","default":false}
  },
  "required":["id"],
  "additionalProperties": false
}""")

let wikiGetSchema = parseJson("""{
  "type":"object",
  "properties":{
    "page":{"type":"string","description":"Wiki page name, e.g. Home, About, Roadmap — case sensitive, no path traversal"},
    "rid":{"type":"string","description":"Optional rid/uuid to get specific version, default latest"}
  },
  "required":["page"],
  "additionalProperties": false
}""")

let wikiCreateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "page":{"type":"string","description":"Wiki page name, e.g. Home, must be alphanumeric with -_"},
    "content":{"type":"string","description":"Page content in markdown, max 50000 chars — will be truncated to stay within context budget if larger"},
    "message":{"type":"string","description":"Commit message for wiki change, e.g. 'Update Home page'"},
    "format":{"type":"string","description":"Content format: markdown (default), wiki, html, th1","enum":["markdown","wiki","html","th1"],"default":"markdown"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate wiki creation"}
  },
  "required":["page","content"],
  "additionalProperties": false
}""")

let wikiHistorySchema = parseJson("""{
  "type":"object",
  "properties":{
    "page":{"type":"string","description":"Wiki page name, default Home","default":"Home"},
    "limit":{"type":"integer","description":"Max history entries, default 20","default":20,"minimum":1,"maximum":100}
  },
  "additionalProperties": false
}""")

let wikiDiffSchema = parseJson("""{
  "type":"object",
  "properties":{
    "page":{"type":"string","description":"Wiki page name, e.g. Home"},
    "v1":{"type":"string","description":"First version rid/uuid, default previous version"},
    "v2":{"type":"string","description":"Second version rid/uuid, default latest"},
    "sideBySide":{"type":"boolean","description":"Return side-by-side diff instead of unified, default false","default":false}
  },
  "required":["page"],
  "additionalProperties": false
}""")

let ticketListSchema = parseJson("""{
  "type":"object",
  "properties":{
    "status":{"type":"string","description":"Filter by status: open (default), closed, all","enum":["open","closed","all"],"default":"open"},
    "limit":{"type":"integer","description":"Max tickets, default 50, max 100","default":50,"minimum":1,"maximum":100}
  },
  "additionalProperties": false
}""")

let ticketCreateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "title":{"type":"string","description":"Ticket title, e.g. 'Fix login bypass', max 200 chars"},
    "description":{"type":"string","description":"Ticket description in markdown, steps to reproduce, expected behavior"},
    "type":{"type":"string","description":"Ticket type: bug (default), feature, task, question","enum":["bug","feature","task","question"],"default":"bug"},
    "priority":{"type":"integer","description":"Priority 1=low, 2=medium (default), 3=high, 4=critical","default":2,"minimum":1,"maximum":4},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate ticket creation"}
  },
  "required":["title"],
  "additionalProperties": false
}""")

let ticketCommentSchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"string","description":"Ticket uuid to comment on, e.g. 179225..."},
    "content":{"type":"string","description":"Comment content in markdown"},
    "user":{"type":"string","description":"Comment author, default mcp","default":"mcp"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate comments"}
  },
  "required":["id","content"],
  "additionalProperties": false
}""")

let ticketUpdateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"string","description":"Ticket uuid"},
    "status":{"type":"string","description":"New status: open, closed, fixed, verified","enum":["open","closed","fixed","verified"]},
    "owner":{"type":"string","description":"New owner username"},
    "priority":{"type":"integer","description":"New priority 1-4","minimum":1,"maximum":4},
    "title":{"type":"string","description":"New title"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["id"],
  "additionalProperties": false
}""")

let searchSchema = parseJson("""{
  "type":"object",
  "properties":{
    "query":{"type":"string","description":"FTS5 query, e.g. 'bug fix', supports AND, OR, NOT, prefix* — searched across wiki, tickets, forum, chat, files, commits"},
    "q":{"type":"string","description":"Alias for query"},
    "limit":{"type":"integer","description":"Max results, default 20, max 50","default":20,"minimum":1,"maximum":50},
    "kinds":{"type":"array","items":{"type":"string","enum":["wiki","ticket","forum","chat","file","commit","branch"]},"description":"Filter by kinds, e.g. ['ticket','wiki'], optional"}
  },
  "additionalProperties": false
}""")

let forumListSchema = parseJson("""{
  "type":"object",
  "properties":{
    "limit":{"type":"integer","description":"Max threads, default 20","default":20,"minimum":1,"maximum":100}
  },
  "additionalProperties": false
}""")

let forumGetSchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"string","description":"Forum thread id, e.g. 179225..."},
    "limit":{"type":"integer","description":"Max posts to return, default 50","default":50}
  },
  "required":["id"],
  "additionalProperties": false
}""")

let forumCreateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "title":{"type":"string","description":"Thread title, e.g. 'How to use branches?'"},
    "content":{"type":"string","description":"Thread content in markdown, max 20000 chars"},
    "user":{"type":"string","description":"Author username, default mcp","default":"mcp"},
    "attachment":{"type":"string","description":"Optional attachment URL or filename"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate thread"}
  },
  "required":["title","content"],
  "additionalProperties": false
}""")

let forumPostSchema = parseJson("""{
  "type":"object",
  "properties":{
    "threadId":{"type":"string","description":"Thread id to post reply to"},
    "content":{"type":"string","description":"Reply content in markdown"},
    "user":{"type":"string","description":"Author, default mcp","default":"mcp"},
    "parentId":{"type":"string","description":"Parent post id for nested reply, optional"},
    "attachment":{"type":"string","description":"Attachment URL"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["threadId","content"],
  "additionalProperties": false
}""")

let forumModerationSchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"string","description":"Thread or post id"},
    "pinned":{"type":"boolean","description":"Pin/unpin thread, default true","default":true},
    "locked":{"type":"boolean","description":"Lock/unlock thread"},
    "deleted":{"type":"boolean","description":"Delete/undelete"}
  },
  "required":["id"],
  "additionalProperties": false
}""")

let chatListSchema = parseJson("""{
  "type":"object",
  "properties":{
    "room":{"type":"string","description":"Chat room name, default main","default":"main"},
    "limit":{"type":"integer","description":"Max messages, default 50, max 100","default":50,"minimum":1,"maximum":100}
  },
  "additionalProperties": false
}""")

let chatSendSchema = parseJson("""{
  "type":"object",
  "properties":{
    "room":{"type":"string","description":"Room name, default main","default":"main"},
    "content":{"type":"string","description":"Message content, max 5000 chars — truncated to stay within context budget"},
    "user":{"type":"string","description":"Author, default mcp","default":"mcp"},
    "attachment":{"type":"string","description":"Attachment URL or filename, optional"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID to prevent duplicate messages"}
  },
  "required":["content"],
  "additionalProperties": false
}""")

let sqlSchema = parseJson("""{
  "type":"object",
  "properties":{
    "query":{"type":"string","description":"Read-only SQL query — only SELECT allowed, e.g. 'SELECT * FROM event WHERE type=\\'ci\\' ORDER BY mtime DESC LIMIT 5'. Uses SQLITE_OPEN_READONLY engine enforcement, so INSERT/UPDATE/DELETE/REPLACE/ATTACH/PRAGMA will fail with SQLITE_READONLY"},
    "params":{"type":"array","items":{"type":"string"},"description":"Optional query params for ? placeholders, e.g. ['trunk'] for WHERE branch=?1"}
  },
  "required":["query"],
  "additionalProperties": false
}""")

let statSchema = parseJson("""{"type":"object","properties":{},"additionalProperties": false}""")
let reportSchema = parseJson("""{
  "type":"object",
  "properties":{
    "id":{"type":"integer","description":"Report id 1=open, 2=closed, 3=all, 4=recent, 5=my","default":1,"minimum":1,"maximum":5},
    "sql":{"type":"string","description":"Optional custom SELECT SQL for custom report, e.g. 'SELECT login FROM user', only SELECT allowed"}
  },
  "additionalProperties": false
}""")
let archiveSchema = parseJson("""{
  "type":"object",
  "properties":{
    "branch":{"type":"string","description":"Branch to archive, default trunk","default":"trunk"},
    "path":{"type":"string","description":"Subpath inside repo, default /","default":"/"},
    "format":{"type":"string","description":"Archive format: zip (default) or tar","enum":["zip","tar"],"default":"zip"}
  },
  "additionalProperties": false
}""")
let rebuildSchema = parseJson("""{
  "type":"object",
  "properties":{
    "oldRepo":{"type":"string","description":"Path to source repo file, e.g. /tmp/old.fossil"},
    "newRepo":{"type":"string","description":"Path to destination repo file, e.g. /tmp/new.fossil"},
    "backend":{"type":"string","description":"New backend: sqlite (default), cdb, lmdb, libmdbx, hybrid-cdb, hybrid-lmdb, hybrid-mdbx","enum":["sqlite","cdb","lmdb","libmdbx","hybrid-cdb","hybrid-lmdb","hybrid-mdbx"],"default":"cdb"},
    "batchSize":{"type":"integer","description":"Batch size for batched migration, default 10000","default":10000,"minimum":100,"maximum":100000}
  },
  "required":["oldRepo","newRepo"],
  "additionalProperties": false
}""")
let cloneSchema = parseJson("""{
  "type":"object",
  "properties":{
    "src":{"type":"string","description":"Source repo path or URL, e.g. /tmp/src.fossil or http://localhost:8080"},
    "dst":{"type":"string","description":"Destination repo path, e.g. /tmp/dst.fossil"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["src","dst"],
  "additionalProperties": false
}""")
let syncSchema = parseJson("""{
  "type":"object",
  "properties":{
    "url":{"type":"string","description":"Remote URL, e.g. http://localhost:8080"},
    "repo":{"type":"string","description":"Local repo path, optional — auto-detected if omitted"}
  },
  "required":["url"],
  "additionalProperties": false
}""")
let configSchema = parseJson("""{
  "type":"object",
  "properties":{
    "name":{"type":"string","description":"Config name, e.g. project-name, project-description"},
    "value":{"type":"string","description":"Config value, for get this is ignored"},
    "repo":{"type":"string","description":"Repo path, optional"}
  },
  "required":["name"],
  "additionalProperties": false
}""")
let userListSchema = parseJson("""{"type":"object","properties":{},"additionalProperties": false}""")
let userCreateSchema = parseJson("""{
  "type":"object",
  "properties":{
    "login":{"type":"string","description":"Username, e.g. alice, must be alphanumeric"},
    "password":{"type":"string","description":"Password, will be hashed with SHA1"},
    "capabilities":{"type":"string","description":"Capabilities string, e.g. 'v' for read, 'a' for admin, default 'v'","default":"v"},
    "name":{"type":"string","description":"Full name, optional"},
    "email":{"type":"string","description":"Email, optional"},
    "idempotencyKey":{"type":"string","description":"Idempotency key UUID"}
  },
  "required":["login","password"],
  "additionalProperties": false
}""")
let searchToolsSchema = parseJson("""{
  "type":"object",
  "properties":{
    "query":{"type":"string","description":"Search query to find relevant tools, e.g. 'wiki', 'ticket', 'commit', 'branch' — returns only matching tools to stay within token budget (progressive disclosure pattern)"},
    "domain":{"type":"string","description":"Optional domain filter: vcs, wiki, ticket, forum, chat, search, admin, storage","enum":["vcs","wiki","ticket","forum","chat","search","admin","storage","all"],"default":"all"}
  },
  "additionalProperties": false
}""")
let codeReviewSchema = parseJson("""{
  "type":"object",
  "properties":{
    "file":{"type":"string","description":"File to review, optional — if omitted, reviews all changed files from status"},
    "rev1":{"type":"string","description":"First revision for diff, default HEAD"},
    "rev2":{"type":"string","description":"Second revision, default working tree"},
    "focus":{"type":"string","description":"Review focus: bugs, security, performance, style, all (default)","enum":["bugs","security","performance","style","all"],"default":"all"}
  },
  "additionalProperties": false
}""")
let releaseNotesSchema = parseJson("""{
  "type":"object",
  "properties":{
    "since":{"type":"string","description":"Since date or tag, e.g. '2024-01-01' or 'v1.0.0', default last 20 commits","default":""},
    "branch":{"type":"string","description":"Branch to generate notes for, default trunk","default":"trunk"},
    "limit":{"type":"integer","description":"Max commits to include, default 20","default":20}
  },
  "additionalProperties": false
}""")

# --- Dummy handler (real logic in server.nim) ---
proc dummyHandler(args: JsonNode): JsonNode =
  var txt = "not implemented yet, args: " & $args
  result = newJObject()
  var arr = newJArray()
  var obj = newJObject()
  obj["type"] = newJString("text")
  obj["text"] = newJString(txt)
  arr.add obj
  result["content"] = arr
  result["isError"] = newJBool(false)

proc buildDefaultRegistry*(): McpToolRegistry =
  var reg = newRegistry()

  # --- Progressive disclosure meta-tools (should be listed first for token budget) ---
  reg.registerTool("fossil_search_tools", "Search and discover relevant tools by query — progressive disclosure pattern to stay within token budget. Instead of loading all 65+ tools definitions (22k-55k tokens), search for what you need, e.g. query='wiki' returns wiki tools, query='ticket' returns ticket tools. Use this first to find the right tool, then call it. This is the most efficient way to use MCP with many tools.", searchToolsSchema, dummyHandler, roAnnot("Search Tools - Progressive Disclosure"))
  reg.registerTool("fossil_list_capabilities", "List all capabilities grouped by domain — overview of what Fossil MCP can do, without loading all tool schemas. Returns summary: vcs (status, diff, commit, branch, etc), wiki (list, get, create, history, diff, blame), ticket (list, get, create, comment, history, search), forum (list, get, create, post, pin, lock, search), chat (list, send, rooms, presence), search (FTS5), admin (stat, report, sql, config, user), storage (archive, rebuild, clone, sync). Use this to understand what's available, then use search_tools to get detailed schemas.", emptySchema, dummyHandler, roAnnot("List Capabilities - Overview"))
  reg.registerTool("fossil_health", "Health check — returns server version, storage backends, binary sizes, QBE mode, and quick stats. Use this to verify MCP server is running and to get repo path auto-detection info. Read-only, fast, no side effects.", emptySchema, dummyHandler, roAnnot("Health Check"))
  reg.registerTool("fossil_openapi", "Get OpenAPI 3.0 spec for REST API — returns full OpenAPI JSON with all endpoints, schemas, security schemes. Use this to understand REST API if you need HTTP instead of MCP tools.", emptySchema, dummyHandler, roAnnot("OpenAPI Spec"))

  # --- Core VCS intent tools (outcome-oriented, efficient) ---
  reg.registerTool("fossil_status", "Get working tree status — shows modified, added, deleted, untracked files in checkout. Use when: you need to see what changed before commit or to understand current checkout state. Returns: list of files with status codes M/A/D/?/!/C and checkout/repo paths. Read-only, fast.", statusSchema, dummyHandler, roAnnot("Status - Working Tree"))
  reg.registerTool("fossil_diff", "Show diff for file or all files — uses Myers O(ND) algorithm with heuristic fallback for huge files. Use when: you need to see what changed in working tree vs HEAD, or between two revisions. Returns: unified diff text, truncated to 8000 chars to stay within context budget. Read-only.", diffSchema, dummyHandler, roAnnot("Diff - Myers"))
  reg.registerTool("fossil_commit", "Commit changes with message — creates new manifest and blob, updates event, mlink, tagxref. Use when: you have changes from status/diff and want to commit them. Requires: message (50 chars first line imperative mood). Optional: files list (empty=all), branch (default trunk), user, idempotencyKey (UUID to prevent duplicate commits on retry). Returns: committed rid and uuid prefix. Destructive (creates new artifact) but idempotent if key provided.", commitSchema, dummyHandler, rwAnnot("Commit Changes", destructive=false, idempotent=true))
  reg.registerTool("fossil_smart_commit", "Smart commit — outcome-oriented tool that does status + diff + generates commit message + commits in one call. Use when: you want to commit all changes with auto-generated message based on diff, without manually calling status, diff, and commit separately. This saves 3 tool calls and tokens. Internally calls status to find changed files, diff to see changes, generates conventional commit message, then commits. Optional: branch, user, autoAdd (auto-add untracked source files), idempotencyKey. Returns: commit result with message and rid. This is the most efficient way to commit.", smartCommitSchema, dummyHandler, rwAnnot("Smart Commit - All-in-One", destructive=false, idempotent=true))
  reg.registerTool("fossil_code_review", "Code review — outcome-oriented tool that does status + diff + review in one call. Use when: you need to review working tree changes or a specific file for bugs, security, performance, style. Internally gets diff, then analyzes for bugs, security issues (injection, XSS, auth), performance, best practices. Returns: actionable feedback with severity. Read-only, efficient (1 call instead of 2).", codeReviewSchema, dummyHandler, roAnnot("Code Review - Smart"))
  reg.registerTool("fossil_release_notes", "Generate release notes — outcome-oriented tool that does timeline + groups commits + formats notes in one call. Use when: you need release notes since date/tag. Internally gets timeline (default 20 commits), groups by feature/bugfix/breaking, formats as Features/Bug Fixes/Breaking Changes/Contributors. Returns: formatted release notes. Read-only.", releaseNotesSchema, dummyHandler, roAnnot("Release Notes - Smart"))
  reg.registerTool("fossil_timeline", "Timeline of checkins — shows commit history with filters. Use when: you need to see recent commits, filter by branch/user/since date. Returns: text or json format (specify format param), limited to 20 by default (max 100) to stay within context budget. Read-only, fast via event table.", timelineSchema, dummyHandler, roAnnot("Timeline"))
  reg.registerTool("fossil_branch_list", "List branches — shows all branches with commit count and last mtime from event GROUP BY branch. Use when: you need to see what branches exist. Returns: list of branch names with counts. Read-only.", emptySchema, dummyHandler, roAnnot("Branch List"))
  reg.registerTool("fossil_branch_create", "Create new branch — creates sym tag sym-<name> via tag table. Use when: you need to start new feature branch. Requires: name (alphanumeric with -_), optional from (base branch/rid), idempotencyKey UUID. Returns: branch created message. Idempotent with key.", branchCreateSchema, dummyHandler, rwAnnot("Branch Create", idempotent=true))
  reg.registerTool("fossil_branch_close", "Close branch — marks branch as closed (adds closed tag). Use when: you finished feature branch and want to close it. Requires: name, optional idempotencyKey. Returns: closed message.", branchCloseSchema, dummyHandler, rwAnnot("Branch Close", idempotent=true))
  reg.registerTool("fossil_tag_list", "List tags — shows all tags from tag table with counts. Use when: you need to see tags like v1.0.0. Read-only.", emptySchema, dummyHandler, roAnnot("Tag List"))
  reg.registerTool("fossil_tag_create", "Create tag — creates tag for rid/uuid. Use when: you need to tag a release. Requires: name (e.g. v1.0.0), optional rid (default HEAD), idempotencyKey. Returns: tag created.", tagSchema, dummyHandler, rwAnnot("Tag Create", idempotent=true))
  reg.registerTool("fossil_log", "File history — shows checkin history for specific file via mlink JOIN filename JOIN event JOIN blob. Use when: you need to see who changed file and when. Requires: file path, optional limit. Returns: list of history entries with date, user, comment, rid. Read-only, uses bind ?1 for file.", logSchema, dummyHandler, roAnnot("File History"))
  reg.registerTool("fossil_file_content", "Get file content — gets file content from checkout (working tree) or repo (latest blob via filename table). Use when: you need to read file content. Requires: path (must be inside checkout, path traversal blocked), optional rev (HEAD/working), maxBytes (default 8000 to stay within budget). Returns: content truncated to maxBytes. Read-only.", fileContentSchema, dummyHandler, roAnnot("File Content"))
  reg.registerTool("fossil_file_list", "List files — lists tracked files from filename table with optional glob pattern. Use when: you need to see what files exist in repo. Optional: pattern (*.nim), limit (default 100). Returns: file list. Read-only.", fileListSchema, dummyHandler, roAnnot("File List"))
  reg.registerTool("fossil_blame", "Blame/annotate file — shows who last changed each line via history. Use when: you need to see who wrote each line. Requires: file path inside checkout. Returns: blame lines with lineNum, author, date, content. Read-only.", blameSchema, dummyHandler, roAnnot("Blame"))
  reg.registerTool("fossil_info", "Info about artifact — shows checkin info for rid/uuid via blob JOIN event, plink parents, mlink files, tagxref tags. Use when: you need details about a commit. Requires: rid or uuid. Returns: info text. Read-only.", infoSchema, dummyHandler, roAnnot("Info"))
  reg.registerTool("fossil_graph", "Commit graph — shows graph data for visualization, with layout x=50+(branchHash%5)*120 y=index*60+20, color by branch hash. Use when: you need graph for UI. Optional: branch filter, limit. Returns: json or text. Read-only.", timelineSchema, dummyHandler, roAnnot("Graph"))
  reg.registerTool("fossil_merge", "Merge branch — 3-way merge. Use when: you need to merge branch into current. Requires: branch name, idempotencyKey. Returns: merge result. Destructive (creates commit) but idempotent.", mergeSchema, dummyHandler, rwAnnot("Merge Branch", idempotent=true))
  reg.registerTool("fossil_stash_save", "Save stash — saves working tree changes as blob with unique uuid s<hex>0... and stash table entry. Use when: you need to save WIP. Optional: message (default WIP), idempotencyKey. Returns: stash id. Idempotent.", stashSchema, dummyHandler, rwAnnot("Stash Save", idempotent=true))
  reg.registerTool("fossil_stash_list", "List stashes — shows stashid, comment, ctime from stash table ORDER BY ctime DESC. Use when: you need to see saved stashes. Read-only.", emptySchema, dummyHandler, roAnnot("Stash List"))
  reg.registerTool("fossil_stash_apply", "Apply stash — gets blob by uuid s<hex>0... and returns diff. Use when: you need to restore WIP. Requires: id, optional drop (delete after apply). Returns: blob diff.", stashApplySchema, dummyHandler, roAnnot("Stash Apply"))
  reg.registerTool("fossil_stash_drop", "Drop stash — DELETE FROM stash WHERE stashid=?1 and DELETE FROM blob WHERE uuid=?1 via bind. Use when: you need to delete stash. Requires: id. Returns: ok. Destructive but idempotent.", stashApplySchema, dummyHandler, rwAnnot("Stash Drop", destructive=true, idempotent=true))
  reg.registerTool("fossil_add", "Add files to tracking — inserts into vfile as added with mtime, marks chnged=1 via bind ?1. Use when: you need to add untracked files. Requires: files list, but in MCP version file path via args. Returns: added files. Check path traversal via normalizedPath.", fileContentSchema, dummyHandler, rwAnnot("Add Files", idempotent=true))
  reg.registerTool("fossil_clean", "Clean checkout — removes untracked files. Use when: you need to clean. Returns: cleaned files list. Destructive.", emptySchema, dummyHandler, rwAnnot("Clean", destructive=true))
  reg.registerTool("fossil_revert", "Revert file — reverts file to HEAD version. Use when: you need to undo changes. Requires: file path. Returns: reverted message. Destructive.", fileContentSchema, dummyHandler, rwAnnot("Revert", destructive=true))

  # --- Wiki tools (8) ---
  reg.registerTool("fossil_wiki_list", "List wiki pages — SELECT tagname FROM tag WHERE tagname LIKE 'wiki-%' ORDER BY tagname. Use when: you need to see wiki pages. Returns: list of page names like Home, About. Read-only.", emptySchema, dummyHandler, roAnnot("Wiki List"))
  reg.registerTool("fossil_wiki_get", "Get wiki page — gets latest version via tag t JOIN tagxref x JOIN blob b JOIN event e WHERE t.tagname='wiki-' || ?1 ORDER BY mtime DESC LIMIT 1, then getBlob decompress (fixes \\0 truncation bug). Use when: you need wiki content. Requires: page name (no traversal), optional rid for specific version. Returns: markdown html. Read-only.", wikiGetSchema, dummyHandler, roAnnot("Wiki Get"))
  reg.registerTool("fossil_wiki_create", "Create wiki page — saves as blob with real SHA3 hash via hashBlob, creates tag wiki-<name> and event type='w', auto FTS5 index (search_fts DELETE then INSERT). Use when: you need to create new wiki page. Requires: page name alphanumeric, content markdown max 50k chars (truncated for budget), optional message, format (markdown/wiki/html/th1), idempotencyKey UUID. Returns: rid. Idempotent with key. This is outcome-oriented: does hash, putBlob, tag, event, FTS index in one call.", wikiCreateSchema, dummyHandler, rwAnnot("Wiki Create", idempotent=true))
  reg.registerTool("fossil_wiki_save", "Save/update wiki page — alias for fossil_wiki_create, same logic. Use when: you need to update existing wiki page. Requires: page, content. Returns: rid. Idempotent.", wikiCreateSchema, dummyHandler, rwAnnot("Wiki Save", idempotent=true))
  reg.registerTool("fossil_wiki_history", "Wiki page history — gets history via tagxref JOIN blob JOIN event JOIN tag WHERE tag.tagname=?1 ORDER BY mtime DESC LIMIT ?2, bind. Use when: you need version history for wiki page. Requires: page (default Home), limit. Returns: list of rid, mtime, user, comment. Read-only.", wikiHistorySchema, dummyHandler, roAnnot("Wiki History"))
  reg.registerTool("fossil_wiki_diff", "Wiki diff — shows diff between two wiki versions using diffBlobs Myers. Use when: you need to see what changed between wiki versions. Requires: page, optional v1/v2 rid/uuid (default latest two from history), sideBySide bool (default false for unified, true for side-by-side). Returns: unified or side-by-side diff. Read-only, efficient.", wikiDiffSchema, dummyHandler, roAnnot("Wiki Diff"))
  reg.registerTool("fossil_wiki_blame", "Wiki blame — shows who last edited each line of wiki page. Use when: you need per-line annotation. Requires: page name. Returns: blame lines with lineNum, content, user, mtime, rid. Read-only. MVP: all lines attributed to latest version.", wikiGetSchema, dummyHandler, roAnnot("Wiki Blame"))
  reg.registerTool("fossil_wiki_search", "Search wiki pages — FTS5 search with MATCH ?1, snippet <b>. Use when: you need to search wiki content. Requires: query, optional limit. Returns: search results with snippet. Read-only.", searchSchema, dummyHandler, roAnnot("Wiki Search"))

  # --- Ticket tools (8) ---
  reg.registerTool("fossil_ticket_list", "List tickets — SELECT tkt_uuid, title, status, type, priority, owner, reporter, mtime FROM ticket WHERE status=?1 ORDER BY mtime DESC LIMIT ?2, bind. Use when: you need to see tickets. Optional: status open/closed/all (default open), limit. Returns: list id, title, status. Read-only.", ticketListSchema, dummyHandler, roAnnot("Ticket List"))
  reg.registerTool("fossil_ticket_get", "Get ticket by id — SELECT tkt_uuid, title, desc, status, type, priority, owner, reporter, mtime FROM ticket WHERE uuid=?1, bind. Use when: you need ticket details. Requires: id uuid. Returns: ticket with markdown html, comments. Read-only.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Ticket uuid, e.g. 179225..."}},"required":["id"],"additionalProperties": false}"""), dummyHandler, roAnnot("Ticket Get"))
  reg.registerTool("fossil_ticket_create", "Create new ticket — INSERT INTO ticket(uuid, title, desc, status open, type, priority, owner '', reporter '', ctime, mtime) VALUES(?1..?6) with bind, auto FTS5 index (search_index INSERT OR REPLACE + search_fts DELETE + INSERT). Use when: you need to create bug/feature/task. Requires: title (max 200 chars), optional description markdown, type bug/feature/task/question, priority 1-4, idempotencyKey UUID. Returns: ticket id and title. Idempotent with key. Outcome-oriented: does uuid gen, insert, FTS index in one call.", ticketCreateSchema, dummyHandler, rwAnnot("Ticket Create", idempotent=true))
  reg.registerTool("fossil_ticket_comment", "Add comment to ticket — INSERT INTO ticketchng(tkt_id, rid 0, mtime, login, comment) VALUES(?1..?4) bind, ensure table exists CREATE TABLE IF NOT EXISTS. Use when: you need to comment on ticket. Requires: id ticket uuid, content markdown, optional user (default mcp), idempotencyKey. Returns: comment added. Idempotent.", ticketCommentSchema, dummyHandler, rwAnnot("Ticket Comment", idempotent=true))
  reg.registerTool("fossil_ticket_add_comment", "Add comment to ticket — alias for fossil_ticket_comment, same logic. Use when: you need to add comment. Requires: id, content. Returns: ok. Idempotent.", ticketCommentSchema, dummyHandler, rwAnnot("Ticket Add Comment", idempotent=true))
  reg.registerTool("fossil_ticket_history", "Ticket history — SELECT tkt_mtime, login, tkt_comment FROM ticketchng WHERE tkt_id=?1 ORDER BY mtime DESC LIMIT 50, bind. Use when: you need change history for ticket (timeline of comments/status changes). Requires: id ticket uuid. Returns: history list mtime, user, comment, field. Read-only.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Ticket uuid"}},"required":["id"],"additionalProperties": false}"""), dummyHandler, roAnnot("Ticket History"))
  reg.registerTool("fossil_ticket_search", "Search tickets — FTS5 or LIKE fallback. Use when: you need to search ticket titles/content. Requires: query, limit. Returns: search results. Read-only.", searchSchema, dummyHandler, roAnnot("Ticket Search"))
  reg.registerTool("fossil_ticket_update", "Update ticket — UPDATE ticket SET col=?1, mtime=?2 WHERE uuid=?3 via bind for each field (title, desc, status, owner, type, priority). Use when: you need to change ticket status, owner, priority, title. Requires: id, optional status (open/closed/fixed/verified), owner, priority 1-4, title, idempotencyKey. Returns: updated ticket. Idempotent.", ticketUpdateSchema, dummyHandler, rwAnnot("Ticket Update", idempotent=true))
  reg.registerTool("fossil_ticket_close", "Close ticket — UPDATE ticket SET status='closed', mtime=?1 WHERE uuid=?2 bind. Use when: you need to close ticket. Requires: id, optional idempotencyKey. Returns: closed message. Idempotent.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Ticket uuid"},"idempotencyKey":{"type":"string","description":"Idempotency key UUID"}},"required":["id"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Ticket Close", idempotent=true))

  # --- Forum tools (8) ---
  reg.registerTool("fossil_forum_list", "List forum threads — SELECT from forum_thread ORDER BY last_mtime DESC LIMIT ?1, includes pinned, locked, deleted handling. Use when: you need to see forum threads. Optional: limit. Returns: threads with id, title, user, posts count. Read-only.", forumListSchema, dummyHandler, roAnnot("Forum List"))
  reg.registerTool("fossil_forum_get", "Get forum thread with posts — gets thread and posts via thread_id. Use when: you need thread details and replies. Requires: id thread id, optional limit posts. Returns: thread title, user, posts list with content, mtime, attachment. Read-only.", forumGetSchema, dummyHandler, roAnnot("Forum Get"))
  reg.registerTool("fossil_forum_create", "Create new forum thread with WYSIWYG markdown — INSERT INTO forum_thread + first post in forum_post, auto FTS5 index. Use when: you need to create discussion thread. Requires: title, content markdown max 20k, optional user (default mcp), attachment URL, idempotencyKey UUID. Returns: thread id. Idempotent. Outcome-oriented: does thread + first post + FTS in one call.", forumCreateSchema, dummyHandler, rwAnnot("Forum Create", idempotent=true))
  reg.registerTool("fossil_forum_post", "Post reply to forum thread with attachment support — INSERT INTO forum_post with thread_id, content, user, parentId optional for nested, attachment. Use when: you need to reply to thread. Requires: threadId, content, optional user, parentId, attachment, idempotencyKey. Returns: post id. Idempotent.", forumPostSchema, dummyHandler, rwAnnot("Forum Post Reply", idempotent=true))
  reg.registerTool("fossil_forum_pin", "Pin/unpin forum thread (moderation) — UPDATE forum_thread SET pinned=?1 WHERE id=?2 bind, ALTER TABLE ADD COLUMN pinned if not exists. Use when: you need to pin important thread. Requires: id, pinned bool default true. Returns: pinned message. Idempotent.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Thread id"},"pinned":{"type":"boolean","description":"Pin true/false, default true","default":true}},"required":["id"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Forum Pin", idempotent=true))
  reg.registerTool("fossil_forum_lock", "Lock/unlock forum thread (moderation) — UPDATE forum_thread SET locked=?1. Use when: you need to lock thread to prevent new posts. Requires: id, locked bool. Returns: locked message.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Thread id"},"locked":{"type":"boolean","description":"Lock true/false, default true","default":true}},"required":["id"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Forum Lock", idempotent=true))
  reg.registerTool("fossil_forum_delete", "Delete forum thread (moderation) — UPDATE forum_thread SET deleted=1. Use when: you need to delete thread. Requires: id. Returns: deleted message. Destructive.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Thread id"}},"required":["id"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Forum Delete", destructive=true, idempotent=true))
  reg.registerTool("fossil_forum_edit", "Edit forum post — UPDATE forum_post SET content=?1, edited=1. Use when: you need to edit post. Requires: id post id, content. Returns: edited message. Idempotent.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Post id"},"content":{"type":"string","description":"New content markdown"}},"required":["id","content"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Forum Edit", idempotent=true))
  reg.registerTool("fossil_forum_search", "Search forum posts with FTS5 — uses search_fts MATCH if available else LIKE. Use when: you need to search forum content. Requires: query, limit. Returns: search results with snippet. Read-only.", searchSchema, dummyHandler, roAnnot("Forum Search"))
  reg.registerTool("fossil_forum_pinned", "List pinned forum threads — SELECT WHERE pinned=1 AND deleted=0 ORDER BY last_mtime DESC. Use when: you need pinned threads. Read-only.", forumListSchema, dummyHandler, roAnnot("Forum Pinned"))

  # --- Chat tools (10) ---
  reg.registerTool("fossil_chat_list", "List chat messages with attachments — SELECT from chat_message WHERE room=?1 ORDER BY mtime DESC LIMIT ?2, includes attachment, edited. Use when: you need to see chat history in room. Optional: room default main, limit default 50. Returns: messages with user, mtime, content, attachment. Read-only.", chatListSchema, dummyHandler, roAnnot("Chat List"))
  reg.registerTool("fossil_chat_send", "Send chat message with attachment and auto FTS5 index — INSERT INTO chat_message with room, content, user, attachment, mtime. Use when: you need to send message to chat room. Requires: content max 5k (truncated for budget), optional room default main, user default mcp, attachment URL, idempotencyKey UUID. Returns: message sent. Idempotent with key. Outcome-oriented: does insert + FTS index in one call.", chatSendSchema, dummyHandler, rwAnnot("Chat Send", idempotent=true))
  reg.registerTool("fossil_chat_edit", "Edit chat message — UPDATE chat_message SET content=?1, edited=1 WHERE id=?2 bind. Use when: you need to edit message. Requires: id, content. Returns: edited message. Idempotent.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Message id"},"content":{"type":"string","description":"New content"}},"required":["id","content"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Edit", idempotent=true))
  reg.registerTool("fossil_chat_delete", "Delete chat message — DELETE FROM chat_message WHERE id=?1 bind. Use when: you need to delete message. Requires: id. Returns: deleted. Destructive.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Message id"}},"required":["id"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Delete", destructive=true, idempotent=true))
  reg.registerTool("fossil_chat_rooms", "List chat rooms — SELECT room, owner, is_private, created FROM chat_room ORDER BY room. Use when: you need to see what chat rooms exist. Returns: rooms list with owner, private flag. Read-only.", emptySchema, dummyHandler, roAnnot("Chat Rooms"))
  reg.registerTool("fossil_chat_create_room", "Create chat room (public/private) — INSERT INTO chat_room(room, owner, is_private, created) VALUES(?1..?4) bind, CREATE TABLE IF NOT EXISTS. Use when: you need new room. Requires: room name, optional owner (default mcp), privateRoom bool default false. Returns: room created. Idempotent.", parseJson("""{"type":"object","properties":{"room":{"type":"string","description":"Room name, e.g. dev, random"},"owner":{"type":"string","description":"Owner username, default mcp","default":"mcp"},"privateRoom":{"type":"boolean","description":"Private room true/false, default false","default":false}},"required":["room"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Create Room", idempotent=true))
  reg.registerTool("fossil_chat_delete_room", "Delete chat room — DELETE FROM chat_room WHERE room=?1 bind. Use when: you need to delete room. Requires: room. Returns: deleted. Destructive.", parseJson("""{"type":"object","properties":{"room":{"type":"string","description":"Room name"}},"required":["room"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Delete Room", destructive=true, idempotent=true))
  reg.registerTool("fossil_chat_presence", "List presence in room (online, typing) — SELECT user, room, last_seen, typing, status FROM chat_presence WHERE room=?1 AND last_seen > now-300s, presence updated via INSERT OR REPLACE. Use when: you need to see who's online/typing in room. Optional: room default main. Returns: presence list user, status, typing bool, lastSeen. Read-only.", chatListSchema, dummyHandler, roAnnot("Chat Presence"))
  reg.registerTool("fossil_chat_presence_update", "Update presence (typing indicator) — INSERT OR REPLACE INTO chat_presence(user, room, last_seen, typing, status) VALUES(?1..?5) bind. Use when: you need to show typing indicator or online status. Requires: room default main, user default mcp, typing bool default false. Returns: presence updated. Idempotent.", parseJson("""{"type":"object","properties":{"room":{"type":"string","description":"Room name, default main","default":"main"},"user":{"type":"string","description":"Username, default mcp","default":"mcp"},"typing":{"type":"boolean","description":"Typing true/false, default false","default":false},"status":{"type":"string","description":"Status online/offline/away, default online","default":"online"}},"required":[],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Presence Update", idempotent=true))
  reg.registerTool("fossil_chat_attachment", "Add attachment to chat message — UPDATE chat_message SET attachment=?1 WHERE id=?2 bind. Use when: you need to attach file URL to existing message. Requires: id message id, attachment URL/filename. Returns: attachment added. Idempotent.", parseJson("""{"type":"object","properties":{"id":{"type":"string","description":"Message id"},"attachment":{"type":"string","description":"Attachment URL or filename"}},"required":["id","attachment"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Chat Attachment", idempotent=true))

  # --- Search, Admin, Storage ---
  reg.registerTool("fossil_search", "Full-text search FTS5 across wiki/tickets/forum/chat/files/commits/branches — uses search_fts MATCH ?1 with snippet <b> and rank, fallback LIKE if FTS5 not available. Use when: you need to search across all content. Requires: query (FTS5 syntax, e.g. 'bug fix', supports AND OR NOT prefix*), optional q alias, limit default 20 max 50, kinds array filter e.g. ['ticket','wiki']. Returns: results with id, kind, title, snippet, rank, mtime, truncated to budget. Read-only, efficient.", searchSchema, dummyHandler, roAnnot("Search FTS5"))
  reg.registerTool("fossil_search_reindex", "Reindex FTS5 search — calls reindexAllSqlite which does initSearchIndex + indexFileContents (500 files, skip binary ext png/jpg/zip, skip >200k, skip \\0, first 50k chars as file-<name>) + indexCommits (1000 commits) + indexBranches (sym-%) + wiki tags LIKE 'wiki-%'. Use when: search results stale or after bulk import. Returns: reindexed message. Idempotent.", emptySchema, dummyHandler, rwAnnot("Search Reindex", idempotent=true))
  reg.registerTool("fossil_sql", "Run read-only SQL — only SELECT allowed, uses SQLITE_OPEN_READONLY engine enforcement (sqlite3_open_v2 with 0x00000001), so INSERT/UPDATE/DELETE/REPLACE/ATTACH/PRAGMA/VACUUM will fail with SQLITE_READONLY error. Use when: you need to query repo DB directly. Requires: query string (e.g. 'SELECT * FROM event WHERE type=\\'ci\\' ORDER BY mtime DESC LIMIT 5'), optional params array for ? placeholders. Returns: JSON array of rows, truncated to stay within context budget. Read-only, safe. This is the escape hatch for uncovered requests, but prefer domain tools over raw SQL when possible (domain-oriented pattern).", sqlSchema, dummyHandler, roAnnot("SQL Read-Only"))
  reg.registerTool("fossil_stat", "Repository statistics — SELECT COUNT(*) from 10 tables: event type='ci' for commits, filename, tag LIKE 'sym-%' for branches, tag, tag LIKE 'wiki-%', ticket, forum_thread, forum_post, chat_message, blob COUNT+SUM(size) for artifacts and repoSize. Use when: you need overview of repo. Returns: stats text with commits, files, branches, tags, wiki, tickets, forum threads/posts, chat messages, artifacts, size, first/last commit. Read-only.", statSchema, dummyHandler, roAnnot("Stat"))
  reg.registerTool("fossil_reportlist", "List ticket reports — predefined reports + dynamic counts from ticket table: open (WHERE status='open'), closed, all, recent (mtime > now-7days), my (assigned to current user). Use when: you need to see what reports exist. Returns: reports list id, name, title, count. Read-only.", emptySchema, dummyHandler, roAnnot("Report List"))
  reg.registerTool("fossil_report", "View ticket report by id — SELECT tkt_uuid, title, status, type, priority, mtime FROM ticket WHERE status=... ORDER BY priority DESC, mtime DESC LIMIT ?1 bind. Use when: you need tickets for a report. Optional: id 1=open 2=closed 3=all 4=recent 5=my, sql custom SELECT (only SELECT allowed) for custom report. Returns: report tickets list. Read-only. Supports custom SQL via sql param for advanced reporting.", reportSchema, dummyHandler, roAnnot("Report View"))
  reg.registerTool("fossil_attachlist", "List attachments (from chat, tickets, wiki) — SELECT msg_id, attachment, mtime, user, room FROM chat_message WHERE attachment!='' UNION forum_post attachments. Use when: you need to see attached files. Optional: limit default 50. Returns: attachments list id, filename, size, mtime, user, ticketId/room. Read-only. Now includes both chat and forum attachments.", emptySchema, dummyHandler, roAnnot("Attach List"))
  reg.registerTool("fossil_rss", "RSS feed for timeline — SELECT user, comment, mtime, objid, branch FROM event ORDER BY mtime DESC LIMIT ?1 bind, formats as RSS 2.0 with atom:link. Use when: you need RSS feed. Optional: limit default 20. Returns: RSS XML with items title [branch] comment, link /info?id=objid, pubDate, author. Read-only.", emptySchema, dummyHandler, roAnnot("RSS Feed"))
  reg.registerTool("fossil_leaves", "List leaves (branch heads) — SELECT branch, objid, uuid, mtime, user, comment FROM event JOIN blob WHERE type='ci' GROUP BY branch ORDER BY mtime DESC LIMIT 20, leaves are heads of branches (most recent checkin per branch). Use when: you need branch heads. Optional: limit. Returns: leaves list branch, rid, uuid, mtime, user, comment. Read-only.", emptySchema, dummyHandler, roAnnot("Leaves"))
  reg.registerTool("fossil_archive", "Create ZIP/TAR archive of repository (real binary) — builds archive from latest files on branch via filename table LIMIT 100, uses STORE (no compression) for ZIP and USTAR for TAR with CRC32. Use when: you need to download repo as zip/tar. Optional: branch default trunk, path default /, format zip/tar default zip. Returns: archive file list and instructions for real binary via CLI fossil archive. Read-only.", archiveSchema, dummyHandler, roAnnot("Archive"))
  reg.registerTool("fossil_rebuild", "Rebuild repository with different backend (sqlite, cdb, lmdb, libmdbx, hybrid-cdb, hybrid-lmdb, hybrid-mdbx) batched 10k — copyAllTablesViaAttach for 23 tables via ATTACH DATABASE (config, event, filename, mlink, tag, tagxref, user, private, shun, backlink, unclustered, audit, ticket, ticketchng, forum_thread, forum_post, chat_message, chat_room, chat_presence, forum_moderation, search_index, delta, blob) + migrateToHybrid batched 10k txn for blobs to KV. Use when: you need to migrate storage backend. Requires: oldRepo path, newRepo path, backend enum, batchSize default 10000. Returns: rebuild done message with blob count. Destructive (creates new file) but idempotent if same input.", rebuildSchema, dummyHandler, rwAnnot("Rebuild", destructive=true, idempotent=true))
  reg.registerTool("fossil_clone", "Clone repository — offline via ATTACH 23 tables + rebuild search_fts, or online via HTTP postXfer/getClone. Use when: you need to clone repo file or from URL. Requires: src (path or URL e.g. /tmp/src.fossil or http://localhost:8080), dst path, optional idempotencyKey. Returns: cloned artifacts count + event count. Idempotent.", cloneSchema, dummyHandler, rwAnnot("Clone", idempotent=true))
  reg.registerTool("fossil_sync", "Sync with remote — bidirectional syncExchange with file cards (Ls Lc) and gimme cards (Lc Ls), /xfer handler rebuilds missing events from manifests. Use when: you need to sync local repo with remote URL. Requires: url (e.g. http://localhost:8080), optional repo path. Returns: pulled/pushed counts. OpenWorld (HTTP).", syncSchema, dummyHandler, roOpenAnnot("Sync"))
  reg.registerTool("fossil_push", "Push to remote — two-phase igot -> gimme -> file -> import -> rebuildEvents. Use when: you need to push local commits to remote. Requires: url, optional repo. Returns: pushed count. OpenWorld.", syncSchema, dummyHandler, roOpenAnnot("Push"))
  reg.registerTool("fossil_pull", "Pull from remote — putBlob file cards + rebuildEventsAfterImport. Use when: you need to pull remote commits. Requires: url, optional repo. Returns: pulled count. OpenWorld.", syncSchema, dummyHandler, roOpenAnnot("Pull"))
  reg.registerTool("fossil_config_get", "Get config — SELECT value FROM config WHERE name=?1 bind. Use when: you need repo config like project-name. Requires: name config name, optional repo. Returns: config value. Read-only.", configSchema, dummyHandler, roAnnot("Config Get"))
  reg.registerTool("fossil_config_set", "Set config — INSERT OR REPLACE INTO config(name, value, mtime) VALUES(?1,?2,?3) bind. Use when: you need to set repo config. Requires: name, value, optional repo, idempotencyKey. Returns: config set message. Idempotent.", parseJson("""{"type":"object","properties":{"name":{"type":"string","description":"Config name, e.g. project-name"},"value":{"type":"string","description":"Config value"},"repo":{"type":"string","description":"Repo path, optional"},"idempotencyKey":{"type":"string","description":"Idempotency key UUID"}},"required":["name","value"],"additionalProperties": false}"""), dummyHandler, rwAnnot("Config Set", idempotent=true))
  reg.registerTool("fossil_user_list", "List users — SELECT login, cap, mtime, info FROM user ORDER BY login, parses info JSON for name/email. Use when: you need to see users. Returns: users list login, capabilities, isAdmin, name. Read-only.", userListSchema, dummyHandler, roAnnot("User List"))
  reg.registerTool("fossil_user_create", "Create user — INSERT OR REPLACE INTO user(login, pw, cap, info, mtime) VALUES(?1..?5) bind with hashPassword SHA1. Use when: you need to create new user. Requires: login alphanumeric, password (hashed), optional capabilities default 'v', name, email, idempotencyKey UUID. Returns: user created message. Idempotent. Destructive? No, creates user.", userCreateSchema, dummyHandler, rwAnnot("User Create", idempotent=true))
  reg.registerTool("fossil_security_audit", "Security audit — runs checks for SEC-01..07: login bypass (verifyPassword), CSRF strict (len==0 or invalid), path traversal (normalizedPath startsWith), read-only (REPLACE/ATTACH should fail), XSS (htmlEscape), session validation, SQLi bind. Use when: you need to audit repo for security vulnerabilities. Returns: audit report PASS/FAIL for each SEC. Read-only, efficient outcome-oriented tool that does 6 checks in one call.", emptySchema, dummyHandler, roAnnot("Security Audit - Smart"))
  reg.registerTool("fossil_benchmark", "Benchmark storage backends — runs hybrid_bench with n=1000 put/get for SQLite, CDB, Hybrid-CDB, shows ops/s. Use when: you need performance numbers. Returns: benchmark results text with put/get ops/s and notes. Read-only.", emptySchema, dummyHandler, roAnnot("Benchmark"))
  reg.registerTool("fossil_get_resource", "Get resource — wrapper for resources/read to fetch resource by URI when client doesn't support resources natively. Use when: you need to read resource content like fossil://timeline?limit=100, fossil://status, fossil://branches, fossil://wiki/Home. This is pragmatic bridge pattern for clients that only support tools. Requires: uri (e.g. fossil://wiki/Home). Returns: resource content. Read-only.", parseJson("""{"type":"object","properties":{"uri":{"type":"string","description":"Resource URI, e.g. fossil://timeline?limit=100, fossil://status, fossil://branches, fossil://wiki/Home, docs://architecture"}},"required":["uri"],"additionalProperties": false}"""), dummyHandler, roAnnot("Get Resource - Bridge"))

  reg
