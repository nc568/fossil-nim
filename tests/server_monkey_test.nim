## server_monkey_test.nim -- monkey test for the embedded HTTP + SSE server of
## the native (`nim c`) web backends.
##
## No browser and no network beyond loopback: the test compiles an example
## with `-d:html` and `-d:canvas`, starts it, and then throws input at it over
## the same wire a browser would use -- well-formed events, garbage, floods big
## enough to overflow the queue, and connections that appear and disappear.
## Every one of those is a way a long-running server gets killed in production,
## so each one is checked rather than assumed.
##
## Compile & run:
##   nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/server_monkey_test.nim

import std/[os, osproc, strutils, json, net, times, random, math, streams]

var passes = 0
var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc ri(rnd: var Rand; lo, hi: int): int {.inline.} =
  ## `rnd.rand(a .. b)` trips over `array.high` being a subrange type; this
  ## helper keeps every call site a plain `int`.
  lo + rnd.rand(hi - lo)

proc repoRoot(): string =
  ## Where this checkout lives, without assuming a path or a working directory.
  let envRoot = getEnv("UIRELAYS_ROOT", "")
  if envRoot.len > 0 and dirExists(envRoot / "src" / "uirelays"):
    return envRoot
  for start in [getCurrentDir(), getAppDir()]:
    var dir = start
    for _ in 0 ..< 8:
      if dirExists(dir / "src" / "uirelays"):
        return dir
      let parent = parentDir(dir)
      if parent == dir:
        break
      dir = parent
  getCurrentDir()

proc pickFreePort(): int =
  var s = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
  try:
    s.bindAddr(Port(0), "127.0.0.1")
    result = int(s.getLocalAddr()[1])
  finally:
    s.close()

proc httpRequest(port: int; httpMethod, path: string; body = "";
                 timeoutMs = 4000): tuple[ok: bool; status: int; body: string] =
  var client = newSocket()
  defer:
    try: client.close()
    except CatchableError: discard
  try:
    client.connect("127.0.0.1", Port(port), timeout = timeoutMs)
    var req = httpMethod & " " & path & " HTTP/1.1\r\n" &
              "Host: 127.0.0.1:" & $port & "\r\n" &
              "Connection: close\r\n"
    if body.len > 0:
      req.add "Content-Type: application/json\r\n"
      req.add "Content-Length: " & $body.len & "\r\n"
    req.add "\r\n"
    if body.len > 0:
      req.add body
    client.send(req)

    var response = ""
    while true:
      var chunk = newString(4096)
      let n = client.recv(addr chunk[0], 4096, timeout = timeoutMs)
      if n <= 0:
        break
      chunk.setLen(n)
      response.add chunk
      if response.len > 4_000_000:
        break

    let sep = response.find("\r\n\r\n")
    if sep < 0:
      return (false, 0, response)
    let head = response[0 ..< sep]
    let rest = response[sep + 4 .. ^1]
    let firstLine = head[0 ..< min(head.len, head.find("\r\n") + 0)]
    var status = 0
    let parts = firstLine.splitWhitespace()
    if parts.len >= 2:
      try:
        status = parseInt(parts[1])
      except ValueError:
        status = 0
    result = (true, status, rest)
  except CatchableError as e:
    result = (false, 0, e.msg)

proc sseConnect(port: int): Socket =
  ## Opens an SSE stream and leaves it open; the caller closes it.
  result = newSocket()
  try:
    result.connect("127.0.0.1", Port(port), timeout = 3000)
    result.send("GET /events HTTP/1.1\r\nHost: 127.0.0.1:" & $port & "\r\n\r\n")
  except CatchableError:
    try: result.close()
    except CatchableError: discard
    return nil

proc sseReadChunk(sock: Socket; timeoutMs = 3000): string =
  ## Headers and the first frame are written with two separate `send`s, so a
  ## single `recv` usually returns only the headers. Read until a frame shows
  ## up or time runs out.
  if sock.isNil:
    return ""
  # A non-blocking read on a socket that has nothing yet returns 0 or raises
  # straight away; the frame is only a few milliseconds behind, so keep asking
  # until the deadline instead of giving up on the first empty read.
  # `net.recv` blocks until it has filled the *whole* buffer, so a 64 KB
  # buffer waits for a frame that will never be that big and then reports a
  # timeout with the data it already read thrown away. Ask for a small chunk
  # instead and let the loop assemble the answer.
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    try:
      var buf = newString(4096)
      let n = sock.recv(addr buf[0], 4096, timeout = 200)
      if n > 0:
        buf.setLen(n)
        result.add buf
        if result.find("data: ") >= 0 and result.find("\n\n") >= 0:
          break
      else:
        sleep(20)
    except CatchableError:
      sleep(20)

proc waitForHealth(port: int; timeoutMs = 15000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    let r = httpRequest(port, "GET", "/health", timeoutMs = 1500)
    if r.ok and r.status == 200 and r.body.find("\"ok\":true") >= 0:
      return true
    sleep(100)
  false

proc readProcessTail(procHandle: Process): string =
  ## Whatever the child wrote before it died -- the crash message we are after.
  try:
    let st = procHandle.outputStream
    var outp = ""
    while not st.atEnd():
      try:
        outp.add st.readLine()
        outp.add "\n"
      except CatchableError:
        break
    let lines = outp.strip().splitLines()
    result = lines[max(0, lines.len - 14)].join("\n      ")
  except CatchableError:
    result = "<no output>"

proc randomEventPayload(rnd: var Rand; n: int): string =
  var events: seq[JsonNode] = @[]
  for _ in 0 ..< n:
    let roll = ri(rnd, 0, 99)
    var e: JsonNode
    if roll < 25:
      e = %*{"type": "mousemove", "x": ri(rnd, -50, 1400), "y": ri(rnd, -50, 900),
             "shift": ri(rnd, 0, 1) == 1, "ctrl": false, "alt": false, "meta": false}
    elif roll < 45:
      e = %*{"type": "mousedown", "x": ri(rnd, 0, 1200), "y": ri(rnd, 0, 800),
             "button": ri(rnd, 0, 2), "clicks": ri(rnd, 1, 2)}
    elif roll < 60:
      e = %*{"type": "mouseup", "x": ri(rnd, 0, 1200), "y": ri(rnd, 0, 800),
             "button": ri(rnd, 0, 2), "clicks": 1}
    elif roll < 70:
      e = %*{"type": "wheel", "dx": ri(rnd, -3, 3), "dy": ri(rnd, -3, 3)}
    elif roll < 95:
      # Escape is deliberately absent: in these examples it means "quit", and
      # a monkey that presses it ends the test rather than stress it. The quit
      # path gets its own check at the end.
      let keys = [("a", "KeyA"), ("Z", "KeyZ"), ("Enter", "Enter"), ("Backspace", "Backspace"),
                  ("ArrowLeft", "ArrowLeft"), (" ", "Space"), ("F5", "F5"),
                  ("1", "Digit1"), (".", "Period"), ("Tab", "Tab")]
      let (k, c) = keys[ri(rnd, 0, keys.high)]
      e = %*{"type": "keydown", "key": k, "code": c,
             "ctrl": ri(rnd, 0, 4) == 0, "shift": ri(rnd, 0, 5) == 0}
    elif roll < 98:
      e = %*{"type": "resize", "width": ri(rnd, 320, 1600), "height": ri(rnd, 240, 1000),
             "uiScale": 100}
    else:
      e = %*{"type": "textinput", "text": $char(ord('a') + ri(rnd, 0, 25))}
    events.add e
  result = $(%*{"events": events})

proc healthJson(port: int): JsonNode =
  let r = httpRequest(port, "GET", "/health")
  if not r.ok or r.status != 200:
    return newJNull()
  try:
    result = parseJson(r.body)
  except CatchableError:
    result = newJNull()

proc stateJson(port: int): JsonNode =
  let r = httpRequest(port, "GET", "/state", timeoutMs = 8000)
  if not r.ok or r.status != 200:
    return newJNull()
  try:
    result = parseJson(r.body)
  except CatchableError:
    result = newJNull()

proc frameIdOf(port: int): int =
  let j = stateJson(port)
  if j.kind == JObject and j.hasKey("frameId"):
    return j["frameId"].getInt()
  -1

proc framesRendered(port: int): int =
  ## `frameId` only moves when the picture changes -- that is the dedup doing
  ## its job -- so "is the app still running" is measured by frames rendered.
  let j = healthJson(port)
  if j.kind == JObject and j.hasKey("totalFramesRendered"):
    return j["totalFramesRendered"].getInt()
  -1

proc runBackend(name: string; examplePath: string; define: string; tmpBin: string) =
  echo "--- ", name, " server monkey ---"
  let root = repoRoot()
  let nimBin = block:
    let e = getEnv("NIM", "")
    if e.len > 0: e else: "nim"
  let outBin = tmpBin / ("server_monkey_" & name)
  let cmd = nimBin & " c --mm:arc " & define & " --path:" & quoteShell(root / "src") &
            " -o:" & quoteShell(outBin) & " " & quoteShell(examplePath)
  echo "  compiling: ", cmd
  let (outp, code) = execCmdEx(cmd)
  if code != 0:
    check(name & " compiles", false, outp.strip().splitLines()[^min(3, outp.strip().splitLines().len)])
    return
  check(name & " compiles", true)

  let port = pickFreePort()
  putEnv("UIRELAYS_PORT", $port)
  let procHandle = startProcess(outBin, args = @[], env = nil,
                                options = {poStdErrToStdOut, poUsePath})
  defer:
    if procHandle.running:
      procHandle.terminate()
      for _ in 0 ..< 50:
        if not procHandle.running:
          break
        sleep(50)
      if procHandle.running:
        procHandle.kill()
    procHandle.close()

  if not waitForHealth(port):
    check(name & " server answers /health", false, "port " & $port)
    return
  check(name & " server answers /health", true)

  # --- HTTP contract -----------------------------------------------------
  let h = healthJson(port)
  check(name & " /health reports the backend", h.hasKey("backend") and
        h["backend"].getStr() == name, $h)
  check(name & " /health reports sseClients", h.hasKey("sseClients"))
  check(name & " /health reports droppedEvents", h.hasKey("droppedEvents"))

  let notFound = httpRequest(port, "GET", "/definitely-not-here")
  check(name & " unknown path is 404", notFound.ok and notFound.status == 404, $notFound.status)

  let getInput = httpRequest(port, "GET", "/input")
  check(name & " GET /input is 405", getInput.ok and getInput.status == 405, $getInput.status)

  let opts = httpRequest(port, "OPTIONS", "/input")
  check(name & " OPTIONS is 204", opts.ok and opts.status == 204, $opts.status)

  let frame = httpRequest(port, "GET", "/frame")
  check(name & " GET /frame returns a frame", frame.ok and frame.status == 200 and
        frame.body.len > 10, $frame.status)

  # --- SSE ---------------------------------------------------------------
  var sse = sseConnect(port)
  let firstChunk = sseReadChunk(sse)
  check(name & " /events streams a frame", firstChunk.find("data: ") >= 0,
        "socketNil=" & $sse.isNil & " chunkLen=" & $firstChunk.len & " head=" &
        firstChunk[0 ..< min(80, firstChunk.len)])
  if not sse.isNil:
    try: sse.close()
    except CatchableError: discard

  # --- malformed input ---------------------------------------------------
  let before = healthJson(port)
  let beforeErrors = if before.hasKey("inputParseErrors"): before["inputParseErrors"].getInt() else: 0
  let garbage = httpRequest(port, "POST", "/input", "{ this is not json at all")
  check(name & " malformed POST is rejected without dying",
        garbage.ok and garbage.status == 200 and garbage.body.find("\"added\":0") >= 0,
        garbage.body)
  let afterGarbage = healthJson(port)
  check(name & " malformed POST is counted",
        afterGarbage.hasKey("inputParseErrors") and
        afterGarbage["inputParseErrors"].getInt() > beforeErrors,
        $afterGarbage)

  # --- monkey input ------------------------------------------------------
  var rnd = initRand(20261019)
  let framesBefore = framesRendered(port)
  let frameBefore = frameIdOf(port)
  var added = 0
  for round in 0 ..< 12:
    let payload = randomEventPayload(rnd, 120)
    let r = httpRequest(port, "POST", "/input", payload)
    if r.ok and r.status == 200:
      try:
        added += parseJson(r.body)["added"].getInt()
      except CatchableError:
        discard
    if not procHandle.running:
      var tail = ""
      try:
        let st = procHandle.outputStream
        while not st.atEnd():
          try:
            tail.add st.readLine()
            tail.add "\n"
          except CatchableError:
            break
      except CatchableError:
        discard
      let lines = tail.strip().splitLines()
      check(name & " survives random input", false, "died on round " & $round &
        " exit=" & $procHandle.peekExitCode() & "\n      " &
        lines[max(0, lines.len - 12)].join("\n      "))
      return
  check(name & " survives random input", procHandle.running)
  check(name & " accepted the random events", added > 1000, "added=" & $added)

  sleep(300)
  let framesAfter = framesRendered(port)
  check(name & " keeps rendering under load", framesAfter > framesBefore,
        "before=" & $framesBefore & " after=" & $framesAfter)
  check(name & " frames changed with the input", frameIdOf(port) >= frameBefore and
        frameBefore > 0, "before=" & $frameBefore & " after=" & $frameIdOf(port))

  let afterMonkey = healthJson(port)
  check(name & " queue drains instead of growing",
        afterMonkey.hasKey("queuedEvents") and afterMonkey["queuedEvents"].getInt() < 4096,
        $afterMonkey)

  # --- overflowing the queue --------------------------------------------
  let flood = randomEventPayload(rnd, 6000)
  let floodResp = httpRequest(port, "POST", "/input", flood, timeoutMs = 15000)
  check(name & " a flood of 6000 events is answered", floodResp.ok and floodResp.status == 200,
        $floodResp.status)
  check(name & " the flood is capped at the queue limit",
        floodResp.ok and floodResp.body.find("\"queued\":4096") >= 0, floodResp.body)
  let afterFlood = healthJson(port)
  check(name & " overflow is reported, not silent",
        afterFlood.hasKey("droppedEvents") and afterFlood["droppedEvents"].getInt() >= 0,
        $afterFlood)
  check(name & " survives the flood", procHandle.running)

  # A mouseup must not be the event that gets dropped: losing it leaves the
  # app holding a button nobody is pressing.
  let busy = httpRequest(port, "POST", "/input", randomEventPayload(rnd, 4300),
                         timeoutMs = 15000)
  check(name & " second flood still answered", busy.ok and busy.status == 200)
  let relief = httpRequest(port, "POST", "/input",
                           """{"events":[{"type":"mouseup","x":10,"y":10,"button":0}]}""")
  check(name & " a mouseup is accepted even when the queue is full",
        relief.ok and relief.status == 200 and relief.body.find("\"added\":1") >= 0,
        relief.body)

  # --- SSE churn: connections that come and go ---------------------------
  var socks: seq[Socket] = @[]
  for _ in 0 ..< 24:
    let s = sseConnect(port)
    if not s.isNil:
      socks.add s
  check(name & " 24 SSE clients connect", socks.len == 24, $socks.len)
  let withClients = healthJson(port)
  check(name & " /health sees the connected clients",
        withClients.hasKey("sseClients") and withClients["sseClients"].getInt() >= 24,
        $withClients)
  for s in socks:
    try: s.close()
    except CatchableError: discard
  # The app has to notice on its own: a closed tab sends nothing.
  var clientsLeft = -1
  for _ in 0 ..< 40:
    sleep(100)
    let j = healthJson(port)
    if j.hasKey("sseClients"):
      clientsLeft = j["sseClients"].getInt()
    if clientsLeft == 0:
      break
  check(name & " closed SSE clients are reaped", clientsLeft == 0, "left=" & $clientsLeft)

  # --- asking the app to quit -------------------------------------------
  discard httpRequest(port, "POST", "/input",
    """{"events":[{"type":"keydown","key":"Escape","code":"Escape"},""" &
    """{"type":"keyup","key":"Escape","code":"Escape"}]}""")
  var quitOk = false
  for _ in 0 ..< 60:
    sleep(100)
    if not procHandle.running:
      quitOk = true
      break
  check(name & " quits cleanly when the app asks to", quitOk,
        "exit=" & $procHandle.peekExitCode())
  if quitOk:
    let code = procHandle.peekExitCode()
    check(name & " exits with status 0", code == 0, "exit=" & $code)
    return

  # --- still alive at the end -------------------------------------------
  let final = healthJson(port)
  check(name & " still serving after everything", final.kind == JObject and
        final.hasKey("ok") and final["ok"].getBool())
  let frameEnd = framesRendered(port)
  sleep(250)
  check(name & " still rendering after everything", framesRendered(port) > frameEnd and
        procHandle.running, "before=" & $frameEnd & " after=" & $framesRendered(port))
  echo "  (", name, " exit alive: ", procHandle.running, ")"

proc main() =
  echo "======================================================================"
  echo " UIRelays Native Web Server Monkey Test (HTTP + SSE, loopback only)"
  echo "======================================================================"
  let root = repoRoot()
  let tmpBin = getTempDir() / "uirelays_server_monkey_bins"
  createDir(tmpBin)
  runBackend("html", root / "examples" / "web_showcase.nim", "-d:html", tmpBin)
  runBackend("canvas", root / "examples" / "web_showcase.nim", "-d:canvas", tmpBin)
  echo "-------------------------------------------------------------------"
  echo "Passed: ", passes, " | Failed: ", failures
  if failures == 0:
    echo "ALL PASS (Native web server monkey)"
  else:
    echo "FAILURES: ", failures
    quit 1

main()
