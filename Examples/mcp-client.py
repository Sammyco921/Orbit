#!/usr/bin/env python3
"""MCP client example — connects to Orbit's Unix socket and demonstrates initialize/tools/list/tools/call.

Usage:
    ./mcp-client.py                     # List all tools
    ./mcp-client.py call DateTimeTool   # Call a specific tool

Requires: Python 3.6+ (stdlib only, no pip dependencies)
"""

import json
import os
import socket
import sys

SOCKET_PATH = os.path.expanduser("~/Library/Application Support/Orbit/orbit-mcp.sock")


def send_request(sock, method, params=None, request_id=1):
    """Send a JSON-RPC request and return the response."""
    payload = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
    }
    if params is not None:
        payload["params"] = params

    sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))

    # Read response (newline-delimited)
    data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
        if b"\n" in chunk:
            break

    if data:
        return json.loads(data.decode("utf-8"))
    return None


def main():
    if not os.path.exists(SOCKET_PATH):
        print(f"Error: Orbit MCP socket not found at {SOCKET_PATH}")
        print("Make sure Orbit is running.")
        sys.exit(1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(SOCKET_PATH)

    # Step 1: Initialize
    print("=== Initialize ===")
    init_resp = send_request(sock, "initialize", {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "python-client", "version": "1.0"}
    }, request_id=1)
    if init_resp:
        print(json.dumps(init_resp, indent=2))
    print()

    # Step 2: Send initialized notification
    notification = json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"})
    sock.sendall((notification + "\n").encode("utf-8"))

    # Step 3: List tools
    print("=== Tools List ===")
    tools_resp = send_request(sock, "tools/list", request_id=2)
    if not tools_resp or "error" in tools_resp:
        print("Error:", tools_resp)
        sock.close()
        sys.exit(1)

    tools = tools_resp.get("result", {}).get("tools", [])
    print(f"Found {len(tools)} tools:")
    for t in tools:
        req = ",".join(t["inputSchema"].get("required", []))
        print(f"  {t['name']}: {t['description']}" + (f" (required: {req})" if req else ""))
    print()

    # Step 4: Call a tool (if specified)
    if len(sys.argv) >= 2 and sys.argv[1] == "call" and len(sys.argv) >= 3:
        tool_name = sys.argv[2]
        args = {}
        if len(sys.argv) >= 4:
            try:
                args = json.loads(sys.argv[3])
            except json.JSONDecodeError:
                print(f"Invalid arguments JSON: {sys.argv[3]}")
                sock.close()
                sys.exit(1)

        print(f"=== Call Tool: {tool_name} ===")
        call_resp = send_request(sock, "tools/call", {
            "name": tool_name,
            "arguments": args,
        }, request_id=3)
        if call_resp:
            print(json.dumps(call_resp, indent=2))

    sock.close()


if __name__ == "__main__":
    main()
