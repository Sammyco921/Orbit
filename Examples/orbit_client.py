#!/usr/bin/env python3
"""Orbit API client for Python.

Usage:
    python orbit_client.py tools                  # List tools
    python orbit_client.py call <name> <json>     # Call a tool
    python orbit_client.py execute <goal>          # Execute agent goal (SSE)
    python orbit_client.py conversations           # List conversations
    python orbit_client.py memory <query>          # Search memory

Environment variables:
    ORBIT_API_KEY   API key (default: empty)
    ORBIT_PORT      Port (default: 8089)
"""

import json
import os
import sys
import urllib.request
import urllib.error

API_KEY = os.environ.get("ORBIT_API_KEY", "")
PORT = os.environ.get("ORBIT_PORT", "8089")
BASE = f"http://127.0.0.1:{PORT}/api"


def headers():
    h = {"Content-Type": "application/json"}
    if API_KEY:
        h["Authorization"] = f"Bearer {API_KEY}"
    return h


def get(path):
    req = urllib.request.Request(f"{BASE}{path}", headers=headers())
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode()


def post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers())
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode()


def sse_post(path, body):
    """POST and read SSE event stream."""
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}{path}", data=data, headers=headers())
    with urllib.request.urlopen(req) as resp:
        buffer = ""
        while True:
            chunk = resp.read(1).decode()
            if not chunk:
                break
            buffer += chunk
            if buffer.endswith("\n\n"):
                for line in buffer.strip().split("\n"):
                    if line.startswith("event: "):
                        etype = line[7:]
                    elif line.startswith("data: "):
                        edata = line[6:]
                        yield etype, edata
                buffer = ""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    try:
        if cmd == "tools":
            print(get("/tools"))

        elif cmd == "call":
            if len(sys.argv) < 4:
                print("Usage: orbit_client.py call <name> <json>")
                sys.exit(1)
            name = sys.argv[2]
            inp = json.loads(sys.argv[3])
            resp = post("/tools/call", {"name": name, "input": inp})
            print(json.dumps(json.loads(resp), indent=2))

        elif cmd == "execute":
            if len(sys.argv) < 3:
                print("Usage: orbit_client.py execute <goal>")
                sys.exit(1)
            goal = " ".join(sys.argv[2:])
            for etype, edata in sse_post("/agent/execute", {"goal": goal}):
                print(f"[{etype}] {edata}")

        elif cmd == "conversations":
            print(get("/conversations"))

        elif cmd == "memory":
            query = " ".join(sys.argv[2:])
            print(get(f"/memory/search?q={urllib.parse.quote(query)}"))

        elif cmd == "health":
            print(get("/health"))

        else:
            print(f"Unknown command: {cmd}")
            print(__doc__)
            sys.exit(1)

    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
