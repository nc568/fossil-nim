#!/usr/bin/env python3
"""
Example REST API client for Fossil-Nim
"""
import requests
import json

BASE = "http://127.0.0.1:8080"

def main():
    print("GET /api/v1/status")
    try:
        r = requests.get(f"{BASE}/api/v1/status")
        print(r.json())
    except Exception as e:
        print("Failed (is server running?):", e)
        print("Start server with: ./bin/fossil server --api-enable -P 8080")
        return

    print("\nGET /api/v1/timeline?limit=5")
    r = requests.get(f"{BASE}/api/v1/timeline", params={"limit":5})
    print(r.json())

    print("\nGET /api/v1/branches")
    r = requests.get(f"{BASE}/api/v1/branches")
    print(r.json())

if __name__ == "__main__":
    main()
