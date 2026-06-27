#!/bin/bash
# MCP client example — connects to Orbit's Unix socket and lists tools.
# Usage: ./mcp-client.sh
# Requires: socat (brew install socat)

SOCKET="${HOME}/Library/Application Support/Orbit/orbit-mcp.sock"

if [ ! -S "$SOCKET" ]; then
    echo "Error: Orbit MCP socket not found at $SOCKET"
    echo "Make sure Orbit is running."
    exit 1
fi

JSON_RPC='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"shell-client","version":"1.0"}}}'
echo "$JSON_RPC" | socat - UNIX-CONNECT:"$SOCKET"
echo ""

# Wait a moment for initialization
sleep 0.1

JSON_RPC='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
echo "$JSON_RPC" | socat - UNIX-CONNECT:"$SOCKET"
echo ""
