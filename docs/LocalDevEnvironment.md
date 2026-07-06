# Local CCA Dev / Test Environment

A self-contained local environment for running and exercising the Continuous
Clearing Auction (CCA) end to end on a local Anvil chain. It deploys a real
`ContinuousClearingAuction` (Astrea-genesis-shaped, scaled for interactivity)
and writes a deployment manifest for offchain consumers.

A companion web console (live state, tick ladder, simulated ETH bids) lives in
the separate [cca-playground](https://github.com/astrea-foundation/cca-playground)
repository — see its README for the visual walkthrough.

> This is a development/testing harness, **not** the production path. Production
> Genesis Auctions are deployed via [`AstreaGenesisAuctionFactory`](../src/AstreaGenesisAuctionFactory.sol)
> on Ethereum mainnet — see the [Deployment Guide](./DeploymentGuide.md).

## Prerequisites

- [Foundry](https://book.getfoundry.sh) (`anvil`, `forge`, `cast`) — already used by this repo
- `jq` (optional; used in the verification snippets below)

## Quickstart

```bash
# 1. Start Anvil, build, deploy the CCA stack, and write the deployment manifest
./dev/dev-up.sh

# ...interact via the cca-playground console, cast, or scripts...

# 2. Tear down the local chain when done
./dev/dev-down.sh
```

`dev-up.sh` is idempotent: it stops any previous local Anvil, starts a fresh chain
(id `31337`) on `:8545`, redeploys, and rewrites `deployments/local.json`. Re-run
it any time to reset to a clean auction.

Anvil is started with `--prune-history 200000`, which keeps per-block state
snapshots in memory for the whole auction timeline. This makes `anvil_rollback`
(the playground's "travel to the past") reliable at any depth — with the default
retention, rolling back past the retention window silently restores an empty
state (deployed contracts disappear).

### Phase windows

Two env knobs shape the lifecycle so all four phases (pre-genesis → live →
settlement → claim) exist as distinct block windows locally:

```bash
START_DELAY=30 CLAIM_DELAY=50 ./dev/dev-up.sh   # the defaults
```

- `START_DELAY` — blocks between deployment and `startBlock` (the pre-genesis window)
- `CLAIM_DELAY` — blocks between `endBlock` and `claimBlock` (the settlement window)

With the defaults the timeline is roughly: deploy ≈ block 2, start 30, end 330,
claims 380.

## What gets deployed

`script/deploy/DeployLocalCCA.s.sol` deploys, from Anvil account 0:

| Contract | Purpose |
| --- | --- |
| `AstreaLocalToken` (mock ERC20 "ASTREA") | The token being auctioned. 10,000 minted; 1,000 (10%) allocated to the auction. |
| `ContinuousClearingAuctionFactory` | Generic CCA factory, no protocol fee controller. |
| `ContinuousClearingAuction` | The auction, created via the factory, funded and `onTokensReceived()`-notified. |
| `CCALens` | Read-only lens for batched state + tick reads (used by the playground console). |
| `PlaygroundBidLens` | **Dev-only** lens: previews a bid's exact exit/claim outcome (tokens, refund, `exitPartiallyFilledBid` hints) by simulating the calls in an `eth_call` and reverting with the result. Never deploy to a real network. |

### Auction parameters (genesis-shaped, scaled for local use)

| Parameter | Value | Note |
| --- | --- | --- |
| currency | `address(0)` (ETH) | ETH-only bids, like genesis |
| requiredCurrencyRaised | `0` | graduates unconditionally, like genesis |
| protocolFeeController | `address(0)` | none |
| floorPrice | `0.1 ETH/token` (Q96) | same granularity as the genesis example |
| tickSpacing | `0.001 ETH/token` (Q96) | bids snap to these boundaries |
| schedule | 2 steps · 300 blocks · front-loaded | `50000 mps ×100`, then `25000 mps ×200` (sums to 1e7) |
| duration | 300 blocks | vs. genesis 50,400 (7 days) — shortened so it's interactive |

The two-step, front-loaded shape mirrors the genesis schedule; only the supply and
block counts are scaled down so the auction can be driven to completion locally.

## The deployment manifest

`DeployLocalCCA.s.sol` writes `deployments/local.json` (gitignored) with everything
an offchain consumer needs to connect:

```json
{
  "chainId": 31337,
  "rpcUrl": "http://127.0.0.1:8545",
  "token": "0x…", "factory": "0x…", "auction": "0x…", "lens": "0x…", "bidLens": "0x…",
  "startBlock": 30, "endBlock": 330, "claimBlock": 380,
  "deployBlock": 2
}
```

`deployBlock` (added by `dev-up.sh` after the deployment) is the chain head right
after deploy — the earliest block a consumer may roll the chain back to without
un-deploying the contracts.

The [cca-playground](https://github.com/astrea-foundation/cca-playground) repo's
`scripts/sync-artifacts.sh` copies this manifest plus the relevant ABIs from `out/`
and serves the interactive console (bids, tick ladder, mining, claims) against it.

## Verifying against the chain

To cross-check any consumer against chain truth:

```bash
A=$(jq -r .auction deployments/local.json)
cast call $A 'clearingPrice()(uint256)'  --rpc-url http://127.0.0.1:8545
cast call $A 'currencyRaised()(uint256)' --rpc-url http://127.0.0.1:8545
cast call $A 'nextBidId()(uint256)'      --rpc-url http://127.0.0.1:8545
cast balance $A                          --rpc-url http://127.0.0.1:8545   # escrowed ETH == sum of live bids
```

## Files

```
dev/dev-up.sh / dev-down.sh              # start / stop the local environment
script/deploy/DeployLocalCCA.s.sol       # Foundry deploy (+ AstreaLocalToken mock)
script/deploy/PlaygroundBidLens.sol      # dev-only bid-outcome lens for the playground UI
deployments/local.json                   # generated: addresses + rpc (gitignored)
```

## Notes & limitations

- Uses public, well-known Anvil test keys — **local chain only**, never a real network.
