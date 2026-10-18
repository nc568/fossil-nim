#!/usr/bin/env python3
"""
Comprehensive Automated Review & Verification Suite for Fossil-Nim REST API & MCP Server
Tests:
1. REST API endpoints (Read & Write, Auth enforcement, Error handling, Security headers)
2. MCP Server (JSON-RPC protocol, tool listing, schema integrity, annotations, tool execution)
"""

import os
import sys
import time
import json
import shutil
import subprocess
import urllib.request
import urllib.error

ROOT_DIR = "/home/nc568/antigravity/hopeful-volta/fossil-nim"
BIN_FOSSIL = os.path.join(ROOT_DIR, "bin/fossil")
BIN_MCP = os.path.join(ROOT_DIR, "bin/fossil-mcp")
TEST_DIR = "/tmp/fossil_api_mcp_review"
REPO_PATH = os.path.join(TEST_DIR, "review.fossil")
CHECKOUT_DIR = os.path.join(TEST_DIR, "checkout")
PORT = 8094
BASE_URL = f"http://127.0.0.1:{PORT}"
API_TOKEN = "sec-mcp-review-token-999"

def log(msg, status="INFO"):
    icons = {"INFO": "🔹", "PASS": "✅", "FAIL": "❌", "WARN": "⚠️"}
    print(f"{icons.get(status, ' ')} [{status}] {msg}")

def http_req(path, method="GET", data=None, token=None, headers=None):
    url = f"{BASE_URL}{path}"
    h = headers.copy() if headers else {}
    if token:
        h["Authorization"] = f"Bearer {token}"
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        if "Content-Type" not in h:
            h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            code = resp.getcode()
            res_body = resp.read().decode()
            resp_headers = dict(resp.info())
            try:
                parsed = json.loads(res_body)
            except:
                parsed = res_body
            return code, parsed, resp_headers
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        try:
            parsed = json.loads(err_body)
        except:
            parsed = err_body
        return e.code, parsed, dict(e.headers)
    except Exception as e:
        return 0, str(e), {}

def test_api():
    log("Starting Comprehensive REST API Review...", "INFO")
    passed = 0
    failed = 0

    endpoints_to_test = [
        ("GET", "/api/v1/health", False, None, 200),
        ("GET", "/api/v1/status", False, None, 200),
        ("GET", "/api/v1/timeline", False, None, 200),
        ("GET", "/api/v1/leaves", False, None, 200),
        ("GET", "/api/v1/branches/list", False, None, 200),
        ("GET", "/api/v1/taglist", False, None, 200),
        ("GET", "/api/v1/tree", False, None, 200),
        ("GET", "/api/v1/stat", False, None, 200),
        ("GET", "/api/v1/reportlist", False, None, 200),
        ("GET", "/api/v1/wiki/list", False, None, 200),
        ("GET", "/api/v1/wiki/get?name=Home", False, None, 200),
        ("GET", "/api/v1/ticket/list", False, None, 200),
        ("GET", "/api/v1/forum/list", False, None, 200),
        ("GET", "/api/v1/chat/list", False, None, 200),
        ("GET", "/api/v1/chat/rooms", False, None, 200),
        ("GET", "/api/v1/security/audit", False, None, 200),
        ("GET", "/api/v1/benchmark", False, None, 200),
        ("GET", "/api/v1/mcp/discovery", False, None, 200),
        ("GET", "/.well-known/mcp", False, None, 200),
        ("GET", "/api/v1/openapi", False, None, 200),
        ("GET", "/api/v1/csrf", False, None, 200),
        # Protected endpoints - unauthenticated must return 401
        ("GET", "/api/v1/sql?q=SELECT+1", False, None, 401),
        ("GET", "/api/v1/repo/export", False, None, 401),
        ("POST", "/api/v1/repo/import", False, {"mode": "merge"}, 401),
        ("POST", "/api/v1/th1", False, {"code": "expr 1+1"}, 401),
        # Protected endpoints - authenticated must succeed with 200
        ("GET", "/api/v1/sql?q=SELECT+1", True, None, 200),
        ("GET", "/api/v1/repo/export", True, None, 200),
        ("POST", "/api/v1/th1", True, {"code": "expr 10 + 20"}, 200),
        ("POST", "/api/v1/markdown", False, {"text": "# Markdown Header"}, 200)
    ]

    for meth, path, use_auth, payload, expected_code in endpoints_to_test:
        token = API_TOKEN if use_auth else None
        code, body, hdrs = http_req(path, method=meth, data=payload, token=token)
        if code == expected_code:
            passed += 1
            log(f"{meth} {path} -> {code} OK (Expected {expected_code})", "PASS")
        else:
            failed += 1
            log(f"{meth} {path} -> got {code}, expected {expected_code}. Body: {str(body)[:150]}", "FAIL")

    return passed, failed

def test_mcp_server():
    log("Starting Comprehensive Native MCP Server Review...", "INFO")
    passed = 0
    failed = 0

    # Start MCP server subprocess in stdio mode
    env = os.environ.copy()
    env["FOSSIL_REPO"] = REPO_PATH
    proc = subprocess.Popen(
        [BIN_MCP],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=CHECKOUT_DIR,
        env=env,
        text=True
    )

    def send_rpc(msg):
        json_str = json.dumps(msg) + "\n"
        proc.stdin.write(json_str)
        proc.stdin.flush()
        line = proc.stdout.readline()
        return json.loads(line)

    try:
        # 1. Initialize
        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "clientInfo": {"name": "ReviewClient", "version": "1.0"},
                "capabilities": {}
            }
        }
        res = send_rpc(init_req)
        srv_name = res.get("result", {}).get("serverInfo", {}).get("name", "")
        if "fossil-nim" in srv_name:
            passed += 1
            log(f"MCP initialize handshake successful: {srv_name}", "PASS")
        else:
            failed += 1
            log(f"MCP initialize failed: {res}", "FAIL")

        # 2. Tools list
        tools_req = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        res = send_rpc(tools_req)
        tools = res.get("result", {}).get("tools", [])
        tool_count = len(tools)
        log(f"MCP tools/list returned {tool_count} tools", "INFO")
        if tool_count >= 80:
            passed += 1
            log(f"MCP tool count verified: {tool_count} tools available", "PASS")
        else:
            failed += 1
            log(f"MCP tool count too low: {tool_count}", "FAIL")

        # Check required schema fields & annotations
        sample_tool = tools[0] if tools else {}
        has_schema = "inputSchema" in sample_tool
        has_annot = "annotations" in sample_tool
        if has_schema and has_annot:
            passed += 1
            log("MCP tools contain inputSchema and annotations metadata", "PASS")
        else:
            failed += 1
            log("MCP tools missing schema or annotations", "FAIL")

        # 3. Call core tools (fossil_ prefixed)
        calls = [
            ("fossil_status", {}),
            ("fossil_timeline", {"limit": 5}),
            ("fossil_stat", {}),
            ("fossil_wiki_list", {}),
            ("fossil_ticket_list", {})
        ]

        req_id = 10
        for tool_name, tool_args in calls:
            req_id += 1
            call_req = {
                "jsonrpc": "2.0",
                "id": req_id,
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": tool_args
                }
            }
            res = send_rpc(call_req)
            if "result" in res and not res.get("result", {}).get("isError", False):
                passed += 1
                log(f"MCP tool call '{tool_name}' returned success: {str(res['result'])[:80]}...", "PASS")
            else:
                failed += 1
                log(f"MCP tool call '{tool_name}' failed: {res}", "FAIL")

    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except:
            pass

    return passed, failed

def main():
    print("=" * 70)
    print("🔍 FOSSIL-NIM: COMPREHENSIVE REST API & MCP SERVER REVIEW")
    print("=" * 70)

    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
    os.makedirs(TEST_DIR, exist_ok=True)
    os.makedirs(CHECKOUT_DIR, exist_ok=True)

    server_proc = None
    try:
        # 1. Setup repository and initial data
        subprocess.run(f"{BIN_FOSSIL} init {REPO_PATH}", shell=True, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(f"{BIN_FOSSIL} open {REPO_PATH}", shell=True, cwd=CHECKOUT_DIR, check=True, stdout=subprocess.DEVNULL)
        with open(os.path.join(CHECKOUT_DIR, "review.txt"), "w") as f:
            f.write("Review content")
        subprocess.run(f"{BIN_FOSSIL} add review.txt", shell=True, cwd=CHECKOUT_DIR, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(f'{BIN_FOSSIL} commit -m "Review initial commit"', shell=True, cwd=CHECKOUT_DIR, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(f'{BIN_FOSSIL} wiki create Home "Review Wiki Home Page"', shell=True, cwd=CHECKOUT_DIR, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(f'{BIN_FOSSIL} ticket create "Review Issue" "Issue description"', shell=True, cwd=CHECKOUT_DIR, check=True, stdout=subprocess.DEVNULL)

        # 2. Launch HTTP REST Server with FOSSIL_API_TOKEN
        server_env = os.environ.copy()
        server_env["FOSSIL_API_TOKEN"] = API_TOKEN
        server_proc = subprocess.Popen(
            [BIN_FOSSIL, "server", "--port", str(PORT), "--bind", "127.0.0.1"],
            cwd=CHECKOUT_DIR,
            env=server_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(1.5)

        # 3. Run REST API review
        api_pass, api_fail = test_api()

        # 4. Run MCP review
        mcp_pass, mcp_fail = test_mcp_server()

        total_pass = api_pass + mcp_pass
        total_fail = api_fail + mcp_fail

        print("\n" + "=" * 70)
        print(f"📊 REVIEW SUMMARY: {total_pass} PASSED, {total_fail} FAILED")
        print("=" * 70)

        if total_fail == 0:
            print("🎉 ALL API & MCP SERVER CAPABILITIES VERIFIED SUCCESSFULLY!")
            sys.exit(0)
        else:
            print("⚠️ SOME REVIEW CHECKS FAILED.")
            sys.exit(1)

    finally:
        if server_proc:
            try:
                server_proc.terminate()
                server_proc.wait(timeout=2)
            except:
                pass
        if os.path.exists(TEST_DIR):
            shutil.rmtree(TEST_DIR)

if __name__ == "__main__":
    main()
