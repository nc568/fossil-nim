## API Client - Platform agnostic, works for web, TUI, desktop
## Uses xhttp-like abstraction, not dependent on specific HTTP lib

import ../types
import std/[json, tables, options, strutils, asyncdispatch]

type
  HttpMethod* = enum
    hmGet = "GET"
    hmPost = "POST"
    hmPut = "PUT"
    hmDelete = "DELETE"

  ApiRequest* = object
    meth*: HttpMethod
    path*: string
    query*: Table[string, string]
    body*: JsonNode
    headers*: Table[string, string]

  ApiClientConfig* = object
    baseUrl*: string
    token*: string
    timeoutMs*: int

  ApiClient* = object
    config*: ApiClientConfig
    # For web, uses fetch; for TUI, uses httpclient; abstraction

proc defaultApiClientConfig*(): ApiClientConfig =
  ApiClientConfig(baseUrl: "", token: "", timeoutMs: 10000)

proc newApiRequest*(meth: HttpMethod, path: string): ApiRequest =
  ApiRequest(meth: meth, path: path, query: initTable[string,string](), body: newJNull(), headers: initTable[string,string]())

proc withQuery*(req: ApiRequest, key, value: string): ApiRequest =
  var r = req
  r.query[key] = value
  r

proc withBody*(req: ApiRequest, body: JsonNode): ApiRequest =
  var r = req
  r.body = body
  r

proc withToken*(req: ApiRequest, token: string): ApiRequest =
  var r = req
  r.headers["Authorization"] = "Bearer " & token
  r

proc buildUrl*(req: ApiRequest, baseUrl: string): string =
  var url = baseUrl & req.path
  if req.query.len>0:
    url.add "?"
    var first = true
    for k,v in req.query:
      if not first: url.add "&"
      url.add k & "=" & v
      first = false
  url

# Platform agnostic API endpoints - these work for any UI
type
  TimelineParams* = object
    limit*: int
    branch*: Option[string]
    user*: Option[string]
    offset*: int

  SearchParams* = object
    query*: string
    limit*: int
    kinds*: seq[string]
    offset*: int

  FileParams* = object
    name*: string
    rid*: Option[Rid]
    pattern*: string

proc timelineRequest*(params: TimelineParams): ApiRequest =
  var req = newApiRequest(hmGet, "/api/v1/timeline")
  req = req.withQuery("limit", $params.limit)
  if params.branch.isSome: req = req.withQuery("branch", params.branch.get())
  if params.user.isSome: req = req.withQuery("user", params.user.get())
  if params.offset>0: req = req.withQuery("offset", $params.offset)
  req

proc searchRequest*(params: SearchParams): ApiRequest =
  var req = newApiRequest(hmGet, "/api/v1/search")
  req = req.withQuery("q", params.query)
  req = req.withQuery("limit", $params.limit)
  if params.kinds.len>0:
    req = req.withQuery("kind", params.kinds.join(","))
  if params.offset>0:
    req = req.withQuery("offset", $params.offset)
  req

proc fileListRequest*(pattern: string = "", limit: int = 100): ApiRequest =
  var req = newApiRequest(hmGet, "/api/v1/file")
  if pattern.len>0:
    req = req.withQuery("pattern", pattern)
  req = req.withQuery("limit", $limit)
  req

proc fileGetRequest*(params: FileParams): ApiRequest =
  var req = newApiRequest(hmGet, "/api/v1/file")
  req = req.withQuery("name", params.name)
  if params.rid.isSome:
    req = req.withQuery("rid", $int(params.rid.get()))
  req

# For JS frontend, we generate JS code that uses fetch
proc generateJsApiClient*(): string =
  """
// Auto-generated API client - vanilla JS, no frameworks, xhttp style
// Platform agnostic, works in browser, Node, Deno
class ApiClient {
  constructor(baseUrl = '', token = '') {
    this.baseUrl = baseUrl;
    this.token = token || localStorage.getItem('fossil_token') || '';
  }
  
  setToken(token) {
    this.token = token;
    if (token) localStorage.setItem('fossil_token', token);
    else localStorage.removeItem('fossil_token');
  }
  
  buildUrl(path, query = {}) {
    let url = this.baseUrl + path;
    const params = new URLSearchParams();
    for (const [k,v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== '') params.append(k, v);
    }
    const qs = params.toString();
    if (qs) url += '?' + qs;
    return url;
  }
  
  async request(method, path, {query = {}, body = null, headers = {}} = {}) {
    const url = this.buildUrl(path, query);
    const opts = {method, headers: {...headers}};
    if (this.token) opts.headers['Authorization'] = 'Bearer ' + this.token;
    if (body) {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(url, opts);
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (!res.ok) throw new Error(json.error || text);
      return json;
    } catch (e) {
      if (!res.ok) throw new Error(text);
      return {ok: true, data: text};
    }
  }
  
  get(path, query = {}) { return this.request('GET', path, {query}); }
  post(path, body = {}, query = {}) { return this.request('POST', path, {query, body}); }
  
  // Typed endpoints
  timeline(limit = 20, branch = '', user = '') {
    return this.get('/api/v1/timeline', {limit, branch, user});
  }
  
  fileList(pattern = '', limit = 100) {
    return this.get('/api/v1/file', {pattern, limit});
  }
  
  fileGet(name, rid = '') {
    return this.get('/api/v1/file', {name, rid});
  }
  
  search(query, limit = 20, kind = '') {
    return this.get('/api/v1/search', {q: query, limit, kind});
  }
  
  searchReindex() {
    return this.post('/api/v1/search/reindex', {});
  }
  
  wikiList() { return this.get('/api/v1/wiki/list'); }
  wikiGet(name) { return this.get('/api/v1/wiki/get', {name}); }
  wikiSave(name, content, message = '') {
    return this.post('/api/v1/wiki/save', {name, content, message});
  }
  
  ticketList(limit = 20) { return this.get('/api/v1/ticket/list', {limit}); }
  ticketGet(id) { return this.get('/api/v1/ticket/get', {id}); }
  
  forumList(limit = 20) { return this.get('/api/v1/forum/list', {limit}); }
  forumGet(id) { return this.get('/api/v1/forum/get', {id}); }
  forumCreate(title, content, user = '') {
    return this.post('/api/v1/forum/create', {title, content, user});
  }
  
  chatList(room = 'main', limit = 50) {
    return this.get('/api/v1/chat/list', {room, limit});
  }
  chatSend(room, content, user = '') {
    return this.post('/api/v1/chat/send', {room, content, user});
  }
  chatRooms() { return this.get('/api/v1/chat/rooms'); }
  chatPresence(room = 'main') { return this.get('/api/v1/chat/presence', {room}); }
  
  graph(branch = '', limit = 100) {
    return this.get('/api/v1/graph', {branch, limit});
  }
  
  info(rid) { return this.get('/api/v1/info', {rid}); }
  
  status() { return this.get('/api/v1/status'); }
  
  markdown(text) { return this.post('/api/v1/markdown', {text}); }
  th1(code) { return this.post('/api/v1/th1', {code}); }
}

window.ApiClient = ApiClient;
window.api = new ApiClient();
"""
