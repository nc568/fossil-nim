## UI Core - Platform agnostic UI logic
## Decoupled from web, can be used for web, TUI, desktop, mobile

import ../types
import std/[options, tables, json, strutils, times, asyncdispatch]

type
  UiPlatform* = enum
    upWeb = "web"
    upTui = "tui"
    upDesktop = "desktop"
    upMobile = "mobile"
    upCli = "cli"

  UiRoute* = object
    path*: string
    name*: string
    component*: string
    requiresAuth*: bool
    title*: string

  UiState* = object
    currentRoute*: UiRoute
    currentUser*: string
    isAuthenticated*: bool
    theme*: string
    repoPath*: string
    branch*: string
    loading*: bool
    error*: string

  ApiResponse*[T] = object
    ok*: bool
    data*: T
    error*: string
    code*: int

  TimelineEntry* = object
    rid*: Rid
    uuid*: string
    user*: string
    comment*: string
    branch*: string
    mtime*: int64
    tags*: seq[string]

  FileEntry* = object
    name*: string
    rid*: Rid
    size*: int
    mtime*: int64
    isBinary*: bool

  WikiEntry* = object
    name*: string
    content*: string
    mtime*: int64
    user*: string

  TicketEntry* = object
    id*: string
    title*: string
    status*: string
    priority*: int
    owner*: string

  # Platform abstraction
  UiRenderer* = concept r
    r.render(string) is string
    r.renderError(string) is string
    r.renderLoading() is string

  UiApiClient* = concept c
    c.get(string) is Future[JsonNode]
    c.post(string, JsonNode) is Future[JsonNode]

proc defaultRoutes*(): seq[UiRoute] =
  @[
    UiRoute(path: "/", name: "home", component: "home", requiresAuth: false, title: "Home"),
    UiRoute(path: "/timeline", name: "timeline", component: "timeline", requiresAuth: false, title: "Timeline"),
    UiRoute(path: "/file", name: "file", component: "file", requiresAuth: false, title: "Files"),
    UiRoute(path: "/finfo", name: "finfo", component: "file-history", requiresAuth: false, title: "File History"),
    UiRoute(path: "/info", name: "info", component: "info", requiresAuth: false, title: "Check-in Info"),
    UiRoute(path: "/graph", name: "graph", component: "graph", requiresAuth: false, title: "Graph"),
    UiRoute(path: "/wiki", name: "wiki", component: "wiki", requiresAuth: false, title: "Wiki"),
    UiRoute(path: "/wiki/list", name: "wiki-list", component: "wiki-list", requiresAuth: false, title: "Wiki Pages"),
    UiRoute(path: "/wiki/new", name: "wiki-new", component: "wiki-edit", requiresAuth: true, title: "New Wiki"),
    UiRoute(path: "/wiki/edit", name: "wiki-edit", component: "wiki-edit", requiresAuth: true, title: "Edit Wiki"),
    UiRoute(path: "/ticket", name: "ticket", component: "ticket", requiresAuth: false, title: "Ticket"),
    UiRoute(path: "/ticket/list", name: "ticket-list", component: "ticket-list", requiresAuth: false, title: "Tickets"),
    UiRoute(path: "/ticket/new", name: "ticket-new", component: "ticket-edit", requiresAuth: true, title: "New Ticket"),
    UiRoute(path: "/forum", name: "forum", component: "forum", requiresAuth: false, title: "Forum"),
    UiRoute(path: "/forum/list", name: "forum-list", component: "forum-list", requiresAuth: false, title: "Forum Threads"),
    UiRoute(path: "/forum/new", name: "forum-new", component: "forum-edit", requiresAuth: true, title: "New Thread"),
    UiRoute(path: "/chat", name: "chat", component: "chat", requiresAuth: false, title: "Chat"),
    UiRoute(path: "/chat/rooms", name: "chat-rooms", component: "chat-rooms", requiresAuth: false, title: "Chat Rooms"),
    UiRoute(path: "/search", name: "search", component: "search", requiresAuth: false, title: "Search"),
    UiRoute(path: "/login", name: "login", component: "login", requiresAuth: false, title: "Login"),
    UiRoute(path: "/setup", name: "setup", component: "setup", requiresAuth: true, title: "Setup"),
    UiRoute(path: "/diff", name: "diff", component: "diff", requiresAuth: false, title: "Diff"),
    UiRoute(path: "/blame", name: "blame", component: "blame", requiresAuth: false, title: "Blame"),
  ]

proc findRoute*(path: string): UiRoute =
  for r in defaultRoutes():
    if r.path == path or path.startsWith(r.path & "?") or path.startsWith(r.path & "/"):
      return r
  # Try prefix match for dynamic routes like /wiki?name=...
  let basePath = path.split("?")[0]
  for r in defaultRoutes():
    if r.path == basePath:
      return r
  UiRoute(path: path, name: "not-found", component: "not-found", requiresAuth: false, title: "Not Found")

proc newUiState*(): UiState =
  UiState(
    currentRoute: findRoute("/"),
    currentUser: "",
    isAuthenticated: false,
    theme: "light",
    repoPath: "",
    branch: "trunk",
    loading: false,
    error: ""
  )

# API response helpers - platform agnostic
proc apiOk*[T](data: T): ApiResponse[T] =
  ApiResponse[T](ok: true, data: data, error: "", code: 200)

proc apiError*[T](msg: string, code: int = 400): ApiResponse[T] =
  ApiResponse[T](ok: false, error: msg, code: code)

# State management - pure functions, no side effects, testable
proc navigate*(state: var UiState, path: string) =
  state.currentRoute = findRoute(path)
  state.loading = true
  state.error = ""

proc setUser*(state: var UiState, user: string, authenticated: bool) =
  state.currentUser = user
  state.isAuthenticated = authenticated

proc setTheme*(state: var UiState, theme: string) =
  state.theme = theme

proc setError*(state: var UiState, error: string) =
  state.error = error
  state.loading = false

proc clearError*(state: var UiState) =
  state.error = ""
