## Router for web UI

import std/[tables, strutils]

type
  RouteHandler* = proc(path: string, query: Table[string,string]): string {.gcsafe.}

  Router* = object
    routes*: Table[string, RouteHandler]
    prefixRoutes*: seq[tuple[prefix: string, handler: RouteHandler]]

proc newRouter*(): Router = Router(routes: initTable[string, RouteHandler](), prefixRoutes: @[])

proc addRoute*(router: var Router, path: string, handler: RouteHandler) =
  router.routes[path]=handler

proc addPrefixRoute*(router: var Router, prefix: string, handler: RouteHandler) =
  router.prefixRoutes.add (prefix: prefix, handler: handler)

proc dispatch*(router: Router, path: string, query: Table[string,string]): string =
  if router.routes.hasKey(path):
    return router.routes[path](path, query)
  for (pref, handler) in router.prefixRoutes:
    if path.startsWith(pref):
      return handler(path, query)
  "<html><body>404 Not Found: " & path & "</body></html>"

# Example handlers
proc timelineHandler(path: string, query: Table[string,string]): string =
  "<html><body><h1>Timeline</h1></body></html>"

proc infoHandler(path: string, query: Table[string,string]): string =
  "<html><body><h1>Info</h1></body></html>"

proc defaultRouter*(): Router =
  var r = newRouter()
  r.addRoute("/", timelineHandler)
  r.addRoute("/timeline", timelineHandler)
  r.addRoute("/info", infoHandler)
  r.addPrefixRoute("/api/", proc(p: string, q: Table[string,string]): string = """{"ok":true}""")
  r
