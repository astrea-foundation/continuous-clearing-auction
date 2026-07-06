#!/usr/bin/env bash
#
# dev-up.sh — stand up the full local CCA dev/test environment end to end.
#
#   1. (re)starts a local Anvil chain (chain id 31337) on :8545
#   2. builds the contracts
#   3. deploys the local CCA stack (token + factory + auction + lens) and funds it
#   4. writes the deployment manifest to deployments/local.json (done by the Foundry script)
#
# The web console lives in the separate cca-playground repo, which consumes
# deployments/local.json and the ABIs in out/ via its scripts/sync-artifacts.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RPC="${RPC:-http://127.0.0.1:8545}"
PORT="${PORT:-8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
# Default Anvil account 0 (public, well-known test key — local chain only).
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
# Phase windows (blocks): a pre-genesis window before the auction opens and a
# settlement window between the end block and claims opening, so all four
# lifecycle phases exist on the local chain (consumed by DeployLocalCCA.s.sol).
export START_DELAY="${START_DELAY:-30}"
export CLAIM_DELAY="${CLAIM_DELAY:-50}"

echo "▸ Ensuring port :$PORT is free"
# Only target the process LISTENING on the port (an old Anvil), not client
# connections (e.g. a browser talking to the RPC), which also show up in lsof.
listener() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true; }
PIDS="$(listener)"
if [ -n "$PIDS" ]; then
  echo "  Stopping listener(s): $PIDS"
  kill $PIDS 2>/dev/null || true
  for _ in $(seq 1 40); do
    [ -z "$(listener)" ] && break
    sleep 0.25
  done
  if [ -n "$(listener)" ]; then
    echo "  Force-killing: $(listener)"
    kill -9 $(listener) 2>/dev/null || true
    sleep 1
  fi
fi

echo "▸ Starting Anvil (chain $CHAIN_ID) on :$PORT"
nohup anvil --host 127.0.0.1 --port "$PORT" --chain-id "$CHAIN_ID" > "$ROOT/anvil.log" 2>&1 &
echo $! > "$ROOT/.anvil.pid"

echo "▸ Waiting for Anvil…"
for _ in $(seq 1 40); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || { echo "✗ Anvil did not start — see anvil.log"; exit 1; }

echo "▸ Building contracts"
forge build >/dev/null 2>&1

echo "▸ Deploying local CCA stack"
mkdir -p deployments
forge script script/deploy/DeployLocalCCA.s.sol:DeployLocalCCAScript \
  --rpc-url "$RPC" --private-key "$DEPLOYER_PK" --broadcast \
  2>&1 | sed -n '/== Logs ==/,/ONCHAIN EXECUTION COMPLETE/p'

# Record the chain head right after deployment: the earliest block the playground's
# time machine may roll back to without un-deploying the contracts.
DEPLOY_BLOCK="$(cast block-number --rpc-url "$RPC")"
jq --argjson b "$DEPLOY_BLOCK" '. + {deployBlock: $b}' deployments/local.json > deployments/local.json.tmp \
  && mv deployments/local.json.tmp deployments/local.json

echo ""
echo "✓ Local CCA environment is up."
echo "  RPC:        $RPC"
echo "  Manifest:   deployments/local.json"
echo "  Console:    see the cca-playground repo (scripts/dev.sh)"
