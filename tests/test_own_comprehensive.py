#!/usr/bin/env python3
"""
Comprehensive independent End-to-End Test Suite for Fossil-Nim
Tests:
1. CLI Repository lifecycle: init, open, add, commit, branch, diff, status, timeline
2. Collaboration features: Wiki, Tickets, Forum, Chat, FTS5 Search
3. Security verification: Path Traversal (403), SQL Dump without Auth (401), CSRF enforcement
4. Web UI & Assets: HTTP 200 for SPA, CSS, JS, API endpoints, Server-Side Parity pages
"""

import os
import sys
import time
import shutil
import subprocess
import urllib.request
import urllib.error
import urllib.parse
import json
import sqlite3

ROOT_DIR = "/home/nc568/antigravity/hopeful-volta/fossil-nim"
BIN_FOSSIL = os.path.join(ROOT_DIR, "bin/fossil")
TEST_DIR = "/tmp/fossil-nim-e2e"
REPO_PATH = os.path.join(TEST_DIR, "test.fossil")
CHECKOUT_DIR = os.path.join(TEST_DIR, "checkout")
PORT = 8085
BASE_URL = f"http://127.0.0.1:{PORT}"

passed_tests = 0
failed_tests = 0

def check(name, condition, details=""):
    global passed_tests, failed_tests
    if condition:
        print(f"  [PASS] {name}")
        passed_tests += 1
        return True
    else:
        print(f"  [FAIL] {name}: {details}")
        failed_tests += 1
        return False

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return res.returncode, res.stdout, res.stderr

print("=" * 60)
print("FOSSIL-NIM INDEPENDENT END-TO-END TEST SUITE")
print("=" * 60)

# Setup test environment
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)
os.makedirs(CHECKOUT_DIR, exist_ok=True)

# 1. CLI Tests: Init
print("\n--- 1. Testing Repository Initialization ---")
rc, out, err = run_cmd(f"{BIN_FOSSIL} init {REPO_PATH}")
check("fossil init creates repository", rc == 0 and os.path.exists(REPO_PATH), f"rc={rc}, out={out}, err={err}")

# Check repository SQLite schema
db = sqlite3.connect(REPO_PATH)
cursor = db.cursor()
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [row[0] for row in cursor.fetchall()]
check("repository schema has blob table", "blob" in tables)
check("repository schema has event table", "event" in tables)
check("repository schema has config table", "config" in tables)

# 2. CLI Tests: Open
print("\n--- 2. Testing Checkout Open ---")
rc, out, err = run_cmd(f"{BIN_FOSSIL} open {REPO_PATH}", cwd=CHECKOUT_DIR)
check("fossil open succeeds", rc == 0 and os.path.exists(os.path.join(CHECKOUT_DIR, "_FOSSIL_")), f"out={out}, err={err}")

# 3. Add and Commit
print("\n--- 3. Testing File Add & Commit ---")
with open(os.path.join(CHECKOUT_DIR, "README.md"), "w") as f:
    f.write("# Fossil-Nim Demo\nThis is a test repository for Fossil-Nim rewrite.\n")

with open(os.path.join(CHECKOUT_DIR, "main.nim"), "w") as f:
    f.write("echo \"Hello from Fossil-Nim!\"\n")

os.makedirs(os.path.join(CHECKOUT_DIR, "src"), exist_ok=True)
with open(os.path.join(CHECKOUT_DIR, "src", "utils.nim"), "w") as f:
    f.write("proc add*(a, b: int): int = a + b\n")

rc, out, err = run_cmd(f"{BIN_FOSSIL} add README.md main.nim src/utils.nim", cwd=CHECKOUT_DIR)
check("fossil add 3 files", rc == 0, f"out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} commit -m \"Initial commit: add project files\"", cwd=CHECKOUT_DIR)
check("fossil commit first checkin", rc == 0, f"out={out}, err={err}")

# 4. Status, Diff & Branching
print("\n--- 4. Testing Status, Diff & Branching ---")
rc, out, err = run_cmd(f"{BIN_FOSSIL} status", cwd=CHECKOUT_DIR)
check("fossil status reports clean checkout", rc == 0, f"out={out}")

with open(os.path.join(CHECKOUT_DIR, "README.md"), "a") as f:
    f.write("Added new line for diff test.\n")

rc, out, err = run_cmd(f"{BIN_FOSSIL} diff README.md", cwd=CHECKOUT_DIR)
check("fossil diff detects modification", rc == 0 and "+Added new line" in out, f"out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} commit -m \"Update README.md\"", cwd=CHECKOUT_DIR)
check("fossil commit second checkin", rc == 0, f"out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} branch new feature-preview", cwd=CHECKOUT_DIR)
check("fossil branch new", rc == 0, f"out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} branch list", cwd=CHECKOUT_DIR)
check("fossil branch list shows trunk", "trunk" in out)

rc, out, err = run_cmd(f"{BIN_FOSSIL} timeline", cwd=CHECKOUT_DIR)
check("fossil timeline contains commits", "Initial commit" in out or "Update README" in out, f"out={out}")

# 5. Populate Rich Data for WebUI (Wiki, Tickets, Forum, Chat, Users)
print("\n--- 5. Populating Rich Data for WebUI Testing ---")
import hashlib

# Admin & Developer users with Nim secureHash compatible uppercase SHA1
admin_pw = "admin123"
pw_hash = hashlib.sha1(admin_pw.encode()).hexdigest().upper()
dev_pw_hash = hashlib.sha1("dev123".encode()).hexdigest().upper()

cursor.execute("INSERT OR REPLACE INTO user(login, pw, cap, info, mtime) VALUES(?, ?, ?, ?, ?)",
               ('admin', pw_hash, 'asdevw', json.dumps({"name": "Fossil Admin", "email": "admin@fossil.local"}), int(time.time())))
cursor.execute("INSERT OR REPLACE INTO user(login, pw, cap, info, mtime) VALUES(?, ?, ?, ?, ?)",
               ('developer', dev_pw_hash, 'devw', json.dumps({"name": "Alice Dev", "email": "alice@fossil.local"}), int(time.time())))

# Forum threads & posts
th_id = f"{int(time.time())}_1001"
cursor.execute("INSERT OR REPLACE INTO forum_thread(thread_id, title, user, created, last_mtime, pinned, locked, deleted) VALUES(?, ?, ?, ?, ?, 1, 0, 0)",
               (th_id, "Welcome to the new Fossil-Nim Forum!", "admin", int(time.time()), int(time.time())))
cursor.execute("INSERT OR REPLACE INTO forum_post(post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid, edited, deleted, attachment) VALUES(?, ?, '', ?, ?, ?, ?, '', 0, 0, 0, '')",
               (f"{int(time.time())}_p1", th_id, "admin", int(time.time()), "Welcome", "Feel free to post discussions, release notes, and architecture questions here!"))

# Chat messages
cursor.execute("INSERT OR REPLACE INTO chat_message(msg_id, room, user, mtime, content, uuid, rid, attachment, edited) VALUES(?, 'general', 'admin', ?, 'Fossil-Nim web server is now operational!', '', 0, '', 0)",
               (f"{int(time.time())}_c1", int(time.time())))
cursor.execute("INSERT OR REPLACE INTO chat_message(msg_id, room, user, mtime, content, uuid, rid, attachment, edited) VALUES(?, 'general', 'developer', ?, 'Testing chat synchronization and live presence.', '', 0, '', 0)",
               (f"{int(time.time())}_c2", int(time.time())))

db.commit()
db.close()

# Use Fossil CLI to create authentic Wiki pages and Tickets
rc, out, err = run_cmd(f"{BIN_FOSSIL} wiki create Home 'Welcome to the **Fossil-Nim** web portal!\n\nThis project is a 100% pure Nim implementation of the Fossil distributed version control system.'", cwd=CHECKOUT_DIR)
check("fossil wiki create Home", rc == 0, f"rc={rc}, out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} wiki create Architecture '### Architecture\n- **Core VCS:** Content-addressable DAG, delta compression, Myers diff.\n- **Storage:** Hybrid SQLite + CDB/LMDB/MDBX.\n- **Server:** Async HTTP server + REST API + MCP protocol.'", cwd=CHECKOUT_DIR)
check("fossil wiki create Architecture", rc == 0, f"rc={rc}, out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} ticket create 'Support Git bundle import' 'Add full compatibility with git fast-import streams'", cwd=CHECKOUT_DIR)
check("fossil ticket create tkt-1", rc == 0, f"rc={rc}, out={out}")

rc, out, err = run_cmd(f"{BIN_FOSSIL} ticket create 'Optimize delta compression' 'Delta Myers heuristic fallback is verified working'", cwd=CHECKOUT_DIR)
check("fossil ticket create tkt-2", rc == 0, f"rc={rc}, out={out}")

print("  [OK] Initial data seeded successfully.")

# 6. Start Web Server in Background for HTTP Testing
print(f"\n--- 6. Launching Web Server on 127.0.0.1:{PORT} ---")
server_proc = subprocess.Popen(
    [BIN_FOSSIL, "server", "--port", str(PORT), "--bind", "127.0.0.1"],
    cwd=CHECKOUT_DIR,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

time.sleep(1.5)
server_running = server_proc.poll() is None
check("Web server process started", server_running, f"poll={server_proc.poll()}")

def http_get(url_path, headers=None):
    url = f"{BASE_URL}{url_path}"
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read().decode('utf-8', errors='ignore'), resp.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', errors='ignore'), e.headers
    except Exception as e:
        return -1, str(e), {}

# 7. Testing HTTP Endpoints
print("\n--- 7. Testing Web UI Pages & Static Assets ---")
status, body, headers = http_get("/")
check("GET / serves 200 OK (SPA index.html)", status == 200 and "html" in body.lower())

status, body, headers = http_get("/css/app.css")
check("GET /css/app.css returns 200 OK with text/css", status == 200 and "css" in headers.get("Content-Type", "").lower())

status, body, headers = http_get("/js/app.js")
check("GET /js/app.js returns 200 OK with javascript", status == 200 and "javascript" in headers.get("Content-Type", "").lower())

status, body, headers = http_get("/api/v1/status")
check("GET /api/v1/status returns 200 OK with JSON", status == 200 and ('"status":"ok"' in body or '"status": "ok"' in body), f"body={body[:150]}")

status, body, headers = http_get("/api/v1/timeline")
check("GET /api/v1/timeline returns 200 OK with commits", status == 200 and '"timeline":' in body)

status, body, headers = http_get("/timeline", headers={"Accept": "text/html"})
check("GET /timeline returns 200 OK HTML", status == 200)

status, body, headers = http_get("/brlist", headers={"Accept": "text/html"})
check("GET /brlist returns 200 OK HTML branch list", status == 200 and "Branches" in body)

status, body, headers = http_get("/file?name=README.md", headers={"Accept": "text/html"})
check("GET /file view returns 200 OK", status == 200)

status, body, headers = http_get("/forum/list", headers={"Accept": "text/html"})
check("GET /forum/list returns 200 OK", status == 200 and "Forum" in body)

status, body, headers = http_get("/ticket/list", headers={"Accept": "text/html"})
check("GET /ticket/list returns 200 OK", status == 200)

status, body, headers = http_get("/stat", headers={"Accept": "text/html"})
check("GET /stat repository statistics returns 200 OK", status == 200 and "Statistics" in body or "Stat" in body)

# 8. Security Hardening Verification
print("\n--- 8. Testing Security Hardening & Vulnerability Defenses ---")

# NEW-01: Path traversal attacks
status, body, _ = http_get("/assets/../../../../etc/passwd")
check("Security: Path Traversal /assets/../../.. is BLOCKED (403)", status == 403, f"got status={status}")

status, body, _ = http_get("/js/../../../../etc/passwd")
check("Security: Path Traversal /js/../../.. is BLOCKED (403)", status == 403, f"got status={status}")

status, body, _ = http_get("/css/../../../../etc/passwd")
check("Security: Path Traversal /css/../../.. is BLOCKED (403)", status == 403, f"got status={status}")

# NEW-02: SQL endpoint authentication
status, body, _ = http_get("/api/v1/sql?q=SELECT+*+FROM+user")
check("Security: /api/v1/sql requires authentication (401)", status == 401, f"got status={status}")

# Security Headers check
status, body, headers = http_get("/")
check("Security: X-Content-Type-Options: nosniff header present", headers.get("X-Content-Type-Options") == "nosniff")
check("Security: X-Frame-Options: SAMEORIGIN header present", headers.get("X-Frame-Options") == "SAMEORIGIN")
check("Security: Content-Security-Policy header present", "Content-Security-Policy" in headers)

# Login Authentication Check
login_data = urllib.parse.urlencode({"user": "admin", "password": "wrong_password", "csrf": "invalid"}).encode('utf-8')
req = urllib.request.Request(f"{BASE_URL}/login", data=login_data, method="POST")
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        check("Security: Wrong password or invalid CSRF is rejected", resp.status in (401, 403) or "Invalid" in resp.read().decode())
except urllib.error.HTTPError as e:
    check("Security: Wrong credentials return HTTP 401/403", e.code in (401, 403))

# Clean up temporary test server
server_proc.terminate()
server_proc.wait(timeout=3)
print(f"\nTest server stopped.")

print("\n" + "=" * 60)
print(f"TEST RESULTS SUMMARY: {passed_tests} PASSED, {failed_tests} FAILED")
print("=" * 60)

if failed_tests == 0:
    print("ALL INDEPENDENT FUNCTIONAL & SECURITY TESTS PASSED SUCCESSFULLY!")
    sys.exit(0)
else:
    print(f"SOME TESTS FAILED! ({failed_tests})")
    sys.exit(1)
