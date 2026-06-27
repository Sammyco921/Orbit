#!/usr/bin/env bash
# Orbit API shell client
#
# Usage:
#   ./orbit_client.sh tools
#   ./orbit_client.sh call <name> '<json>'
#   ./orbit_client.sh execute '<goal>'
#   ./orbit_client.sh conversations
#   ./orbit_client.sh memory '<query>'
#   ./orbit_client.sh health
#
# Environment:
#   ORBIT_API_KEY   API key (default: empty)
#   ORBIT_PORT      Port (default: 8089)

set -euo pipefail

API_KEY="${ORBIT_API_KEY:-}"
PORT="${ORBIT_PORT:-8089}"
BASE="http://127.0.0.1:${PORT}/api"

auth_header() {
    if [ -n "$API_KEY" ]; then
        echo "-H" "Authorization: Bearer $API_KEY"
    fi
}

cmd="${1:-help}"

case "$cmd" in
    tools)
        curl -s $(auth_header) "${BASE}/tools"
        echo
        ;;
    call)
        if [ $# -lt 3 ]; then
            echo "Usage: $0 call <name> '<json>'" >&2
            exit 1
        fi
        name="$2"
        body="$3"
        curl -s $(auth_header) \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"$name\", \"input\": $body}" \
            "${BASE}/tools/call"
        echo
        ;;
    execute)
        if [ $# -lt 2 ]; then
            echo "Usage: $0 execute '<goal>'" >&2
            exit 1
        fi
        goal="$2"
        curl -s -N $(auth_header) \
            -H "Content-Type: application/json" \
            -d "$(printf '{"goal": "%s"}' "$goal")" \
            "${BASE}/agent/execute"
        echo
        ;;
    conversations)
        curl -s $(auth_header) "${BASE}/conversations"
        echo
        ;;
    memory)
        query="${2:-}"
        encoded=$(printf '%s' "$query" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "$query")
        curl -s $(auth_header) "${BASE}/memory/search?q=${encoded}"
        echo
        ;;
    health)
        curl -s $(auth_header) "${BASE}/health"
        echo
        ;;
    *)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  tools              List all tools"
        echo "  call <n> <j>       Call a tool with JSON input"
        echo "  execute '<goal>'   Execute an agent goal (SSE stream)"
        echo "  conversations      List conversations"
        echo "  memory '<q>'       Search memory"
        echo "  health             Health check"
        exit 1
        ;;
esac
