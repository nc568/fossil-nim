// api.js - Vanilla JS API client, no frameworks, xhttp style
// Platform agnostic, works for web, Node, etc.

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
  
  // Typed endpoints - modular
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
  ticketCreate(title, description, type = 'bug', priority = 2) {
    return this.post('/api/v1/ticket/create', {title, description, type, priority});
  }
  
  forumList(limit = 20) { return this.get('/api/v1/forum/list', {limit}); }
  forumGet(id) { return this.get('/api/v1/forum/get', {id}); }
  forumCreate(title, content, user = '') {
    return this.post('/api/v1/forum/create', {title, content, user});
  }
  forumPost(threadId, content, user = '', parentId = '') {
    return this.post('/api/v1/forum/post', {threadId, content, user, parentId});
  }
  forumPin(id, pinned = true) {
    return this.post('/api/v1/forum/pin', {id, pinned});
  }
  forumLock(id, locked = true) {
    return this.post('/api/v1/forum/lock', {id, locked});
  }
  forumDelete(id) {
    return this.post('/api/v1/forum/delete', {id});
  }
  forumEditPost(id, content) {
    return this.post('/api/v1/forum/edit', {id, content});
  }
  forumPinned(limit = 20) {
    return this.get('/api/v1/forum/pinned', {limit});
  }
  forumSearch(query, limit = 20) {
    return this.get('/api/v1/forum/search', {q: query, limit});
  }
  
  chatList(room = 'main', limit = 50) {
    return this.get('/api/v1/chat/list', {room, limit});
  }
  chatSend(room, content, user = '', attachment = '') {
    if (attachment) return this.post('/api/v1/chat/send', {room, content, user, attachment});
    return this.post('/api/v1/chat/send', {room, content, user});
  }
  chatEdit(id, content) {
    return this.post('/api/v1/chat/edit', {id, content});
  }
  chatDelete(id) {
    return this.post('/api/v1/chat/delete', {id});
  }
  chatAttachment(id, attachment) {
    return this.post('/api/v1/chat/attachment', {id, attachment});
  }
  chatRooms() { return this.get('/api/v1/chat/rooms'); }
  chatCreateRoom(room, owner = '', privateRoom = false) {
    return this.post('/api/v1/chat/room', {room, owner, privateRoom});
  }
  chatDeleteRoom(room) {
    return this.post('/api/v1/chat/room/delete', {room});
  }
  chatPresence(room = 'main') { return this.get('/api/v1/chat/presence', {room}); }
  chatPresenceUpdate(room, user, typing = false) {
    return this.post('/api/v1/chat/presence', {room, user, typing});
  }
  
  graph(branch = '', limit = 100) {
    return this.get('/api/v1/graph', {branch, limit});
  }
  
  info(rid) { return this.get('/api/v1/info', {rid}); }
  diff(from, to) { return this.get('/api/v1/diff', {from, to}); }
  branches() { return this.get('/api/v1/branches'); }
  
  status() { return this.get('/api/v1/status'); }
  
  markdown(text) { return this.post('/api/v1/markdown', {text}); }
  th1(code) { return this.post('/api/v1/th1', {code}); }
  
  login(user, password) {
    return this.post('/login', {user, password});
  }
}

window.ApiClient = ApiClient;
window.api = new ApiClient();

console.log('📡 api.js loaded - vanilla JS API client');
