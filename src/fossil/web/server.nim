## Web server - built-in HTTP server for Fossil UI

import std/[asynchttpserver, asyncdispatch, strutils, tables, json, os]
import ../types
import ../config

type
  WebServer* = object
    config*: FossilConfig
    httpServer*: AsyncHttpServer

proc handleRequest*(req: Request, config: FossilConfig) {.async.} =
  let path = req.url.path
  case path
  of "/", "/index", "/home":
    await req.respond(Http200, "<html><body><h1>Fossil-Nim</h1><p>Trunk</p><a href='/timeline'>Timeline</a></body></html>", newHttpHeaders([("Content-Type","text/html")]))
  of "/timeline":
    await req.respond(Http200, "<html><body><h1>Timeline</h1><p>Checkins...</p></body></html>", newHttpHeaders([("Content-Type","text/html")]))
  of "/api/v1/status":
    await req.respond(Http200, """{"ok":true,"branch":"trunk"}""", newHttpHeaders([("Content-Type","application/json")]))
  else:
    if path.startsWith("/api/"):
      await req.respond(Http404, """{"ok":false,"error":"not found"}""", newHttpHeaders([("Content-Type","application/json")]))
    else:
      await req.respond(Http404, "<html><body>404 Not Found: " & path & "</body></html>", newHttpHeaders([("Content-Type","text/html")]))

proc startWebServer*(config: FossilConfig) {.async.} =
  var server = newAsyncHttpServer()
  proc cb(req: Request) {.async.} =
    await handleRequest(req, config)
  echo "Web server listening on http://", config.apiBind, ":", config.apiPort
  await server.serve(Port(config.apiPort), cb, config.apiBind)

when isMainModule:
  let cfg = defaultConfig()
  waitFor startWebServer(cfg)
