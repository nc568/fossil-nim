#!/usr/bin/env python3
"""
Example MCP client for Fossil-Nim
Shows how AI agent would interact with fossil via MCP
"""
import json
import subprocess
import sys

def send_recv(proc, msg):
    proc.stdin.write((json.dumps(msg) + "\n").encode())
    proc.stdin.flush()
    line = proc.stdout.readline()
    return json.loads(line)

def main():
    fossil_bin = sys.argv[1] if len(sys.argv) > 1 else "./bin/fossil-mcp"
    proc = subprocess.Popen(
        [fossil_bin],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0
    )

    # Initialize
    init_msg = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "example-client", "version": "1.0"}
        }
    }
    print("-> initialize")
    resp = send_recv(proc, init_msg)
    print("<- ", json.dumps(resp, indent=2))

    # List tools
    print("\n-> tools/list")
    resp = send_recv(proc, {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
    print("<- tools:", len(resp["result"]["tools"]), "tools")
    for t in resp["result"]["tools"][:5]:
        print("  -", t["name"], ":", t["description"])

    # Call fossil_status
    print("\n-> tools/call fossil_status")
    resp = send_recv(proc, {
        "jsonrpc":"2.0",
        "id":3,
        "method":"tools/call",
        "params":{"name":"fossil_status","arguments":{}}
    })
    print("<- ", json.dumps(resp, indent=2))

    # Call fossil_timeline
    print("\n-> tools/call fossil_timeline")
    resp = send_recv(proc, {
        "jsonrpc":"2.0",
        "id":4,
        "method":"tools/call",
        "params":{"name":"fossil_timeline","arguments":{"limit":5}}
    })
    print("<- ", json.dumps(resp, indent=2))

    proc.terminate()

if __name__ == "__main__":
    main()
