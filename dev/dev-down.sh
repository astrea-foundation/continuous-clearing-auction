#!/usr/bin/env bash
# dev-down.sh — stop the local Anvil chain started by dev-up.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8545}"

if [ -f "$ROOT/.anvil.pid" ]; then
  PID="$(cat "$ROOT/.anvil.pid")"
  kill "$PID" 2>/dev/null && echo "✓ Stopped Anvil (pid $PID)" || echo "Anvil pid $PID not running"
  rm -f "$ROOT/.anvil.pid"
elif lsof -ti:"$PORT" >/dev/null 2>&1; then
  kill "$(lsof -ti:"$PORT")" && echo "✓ Stopped process on :$PORT"
else
  echo "Nothing to stop on :$PORT"
fi
