# Repo Onboarding Playbook

You know what the product does at a high level. This document gets you from "repository dumb" to
"can verify the fork, deploy to testnet, and wire a frontend" in the shortest path possible. Every
claim in here is checkable with a command, and the commands are included.

## 0. The 60-second version

- This repo is **Uniswap's Continuous Clearing Auction (CCA)**, forked by Astrea. Upstream is the
  `main` branch (audited by Spearbit, OpenZeppelin, ABDK — PDFs in [`docs/audits`](./audits)).
- The Astrea branch (`codex/astrea-genesis-v1`) **does not touch the audited auction engine**. The
  only production Solidity added is one factory ([`src/AstreaGenesisAuctionFactory.sol`](../src/AstreaGenesisAuctionFactory.sol))
  plus its interface. Everything else on the branch is tests, deploy scripts, local dev tooling, and docs.
- The factory deploys a stock `ContinuousClearingAuction` with hardcoded Genesis guardrails:
  mainnet only, ETH bids only, 7 days (50,400 blocks), allocation must be exactly 10% of token
  supply, no minimum raise, no protocol fee, no LP migration.

Prove the "core untouched" claim to yourself right now:

```bash
git diff main...HEAD --stat -- src/
# Expected: only two ADDED files, zero modified:
#   src/AstreaGenesisAuctionFactory.sol             | 146 ++++++
#   src/interfaces/IAstreaGenesisAuctionFactory.sol |  45 +++
```

That single fact shapes your whole study plan: the engine is inherited and audited, the Astrea
surface is ~190 lines. Spend your depth budget accordingly.

## 1. The mental model (read before any code)

### What a CCA is, mechanically

A uniform-price auction stretched over a range of blocks:

1. **Supply drips out per block** according to a fixed schedule (`auctionStepsData`). Rates are in
   **MPS** — milli-basis-points of total supply, where `1e7 MPS = 100%` (`ConstantsLib.MPS`).
2. **Bidders submit `(maxPrice, amount)`** — "I'll spend `amount` of currency at any price up to
   `maxPrice`". Prices live on **ticks**: multiples of `tickSpacing` above `floorPrice`, stored as
   a sorted linked list.
3. Every block with a new bid, the auction **checkpoints**: it recomputes the lowest
   **clearing price** at which all remaining supply sells to demand at-or-above that price.
   The price only ratchets up.
4. Bids strictly **above** clearing fill fully (pro-rata over the blocks they were live); bids
   **at** clearing fill partially; bids **below** are outbid and get refunded on exit.
5. After `endBlock`: bidders `exitBid`/`exitPartiallyFilledBid` (get ETH refunds), then after
   `claimBlock` they `claimTokens`. The team `sweepCurrency()` (raised ETH → `fundsRecipient`)
   and `sweepUnsoldTokens()` (leftover tokens → `tokensRecipient`).

### The three units you must internalize

| Unit | What | Where |
| --- | --- | --- |
| **Q96** | Prices and demand are fixed-point, scaled by `2^96`. A "price" is currency-wei per token-wei × 2^96. | [`src/libraries/FixedPoint96.sol`](../src/libraries/FixedPoint96.sol) |
| **MPS** | Milli-bips of total supply. `1e7` = everything. Issuance schedule and fill accounting use it. | [`src/libraries/ConstantsLib.sol`](../src/libraries/ConstantsLib.sol) |
| **ValueX7** | A `uint256` implicitly ×`1e7`, used to defer division. Variables suffixed `_X7`. | [`src/libraries/ValueX7Lib.sol`](../src/libraries/ValueX7Lib.sol) |

If a formula confuses you, it is almost always one of these scalings. Check the suffix first.

### The one architectural fact

`ContinuousClearingAuction` is a single deployed contract assembled from storage mixins:

```
ContinuousClearingAuction
├── BidStorage         bids by id (owner, maxPrice, amount, startBlock)
├── CheckpointStorage  checkpoints by block (clearing price + accumulators)
├── StepStorage        issuance schedule, SSTORE2-packed; start/end/claim blocks
├── TickStorage        sorted linked list of price ticks + demand per tick
└── AuctionStorage     immutables (token, currency, recipients, ...) + top-level state
```

State is **lazy**: nothing updates until someone bids or calls `checkpoint()`. A view like
`clearingPrice()` can be stale. This bites every integrator once; let it not be you.

### Suggested reading order

1. This file, then the product brief: [`Astrea ICO - Genesis Auction (CCA Fork).md`](<./Astrea%20ICO%20-%20Genesis%20Auction%20(CCA%20Fork).md>) and [`astrea-PLAN-v1.md`](./astrea-PLAN-v1.md) (~20 min).
2. [`TechnicalDocumentation.md`](./TechnicalDocumentation.md) — the entrypoint walkthrough and integration guidelines sections (~40 min).
3. Tier 1 code below (~2–3 h).
4. Tier 2 code, driven by tests (~half a day).
5. Whitepaper ([`docs/assets/whitepaper.pdf`](./assets/whitepaper.pdf)) only if you need the math proofs. Optional.

## 2. Code by importance tier

### Tier 1 — absolute necessities (understand line by line)

| What | Where | Why |
| --- | --- | --- |
| **`AstreaGenesisAuctionFactory`** | [`src/AstreaGenesisAuctionFactory.sol`](../src/AstreaGenesisAuctionFactory.sol) | The *entire* Astrea production delta. 146 lines: constants, `create()`, `getAddress()` (CREATE2 preview), `_auctionParameters()`, `_validateGenesisConfig()`. Read all of it. |
| **`AstreaGenesisAuctionConfig`** | [`src/interfaces/IAstreaGenesisAuctionFactory.sol`](../src/interfaces/IAstreaGenesisAuctionFactory.sol) | The only knobs the operator controls: recipients, `startBlock`, `floorPrice`, `tickSpacing`, optional hook. Everything else is hardcoded. |
| **`AuctionParameters` struct** | [`src/interfaces/IContinuousClearingAuction.sol`](../src/interfaces/IContinuousClearingAuction.sol) | What the factory constructs internally. Know every field and what Astrea pins it to. |
| **Auction external entrypoints** | [`src/ContinuousClearingAuction.sol`](../src/ContinuousClearingAuction.sol) | The full user/operator surface: `onTokensReceived()`, `submitBid()` (both overloads), `checkpoint()`, `forceIterateOverTicks()`, `exitBid()`, `exitPartiallyFilledBid()`, `claimTokens()`, `claimTokensBatch()`, `sweepCurrency()`, `sweepUnsoldTokens()`, plus views (`clearingPrice()`, `isGraduated()`). Skip the internals on first pass — signatures, modifiers, revert conditions, events. |
| **Units & bounds** | [`src/libraries/ConstantsLib.sol`](../src/libraries/ConstantsLib.sol), [`FixedPoint96.sol`](../src/libraries/FixedPoint96.sol) | `MPS = 1e7`, `MIN_FLOOR_PRICE = 2^32 + 1`, `MIN_TICK_SPACING = 2`, `MAX_TOTAL_SUPPLY = 2^100`. Factory validation leans on these. |
| **The Astrea test file** | [`test/AstreaGenesisAuctionFactory.t.sol`](../test/AstreaGenesisAuctionFactory.t.sol) | The executable spec of the fork. Ten tests: guardrail reverts + no-bid / undersubscribed / oversubscribed settlement. Reading this *is* verifying the changes. |

The lifecycle you must be able to recite afterwards:

```
factory.create() → transfer exactly tokenAllocation to auction → onTokensReceived()
→ [startBlock] bids (payable ETH) → lazy checkpoints, price ratchets up
→ [endBlock] final checkpoint() → exits (refunds) → [claimBlock == endBlock] claims
→ sweepCurrency() by fundsRecipient, sweepUnsoldTokens() by tokensRecipient
```

### Tier 2 — should understand (read with tests open)

| What | Where | Why |
| --- | --- | --- |
| **The engine's two hot paths** | `_checkpointAtBlock()` and `_iterateOverTicksAndFindClearingPrice()` in [`ContinuousClearingAuction.sol`](../src/ContinuousClearingAuction.sol) | Where clearing price, rollover, and the accumulators (`cumulativeMps`, `cumulativeMpsPerPrice`, `currencyRaisedAtClearingPriceQ96X7`) are written. Exits derive fills in O(1) from these — understand what each accumulates. |
| **`_submitBid` / `_processExit`** | same file | Escrow in, refund + fill out. Where the validation hook and `MAX_BID_PRICE` are enforced. |
| **Storage mixins** | [`src/TickStorage.sol`](../src/TickStorage.sol), [`BidStorage.sol`](../src/BidStorage.sol), [`CheckpointStorage.sol`](../src/CheckpointStorage.sol), [`StepStorage.sol`](../src/StepStorage.sol), [`AuctionStorage.sol`](../src/AuctionStorage.sol) | Small files. TickStorage's linked list (and the `prevTickPrice` hint) matters most for gas and frontend UX. |
| **Fill/demand math libs** | [`src/libraries/DemandLib.sol`](../src/libraries/DemandLib.sol), [`CheckpointAccountingLib.sol`](../src/libraries/CheckpointAccountingLib.sol), [`StepLib.sol`](../src/libraries/StepLib.sol), [`BidLib.sol`](../src/libraries/BidLib.sol), [`PriceLib.sol`](../src/libraries/PriceLib.sol) | The actual arithmetic behind fills and refunds. Read after the hot paths, not before — they make no sense without the call sites. |
| **Lenses** | [`src/lens/CCALens.sol`](../src/lens/CCALens.sol) (= [`AuctionStateLens`](../src/lens/AuctionStateLens.sol) + [`TickDataLens`](../src/lens/TickDataLens.sol) + Multicallable) | Your frontend's read layer. `state()` returns a fresh checkpoint via an `eth_call`-safe revert trick; `getInitializedTickData()` walks the tick ladder. |
| **Generic factory** | [`src/ContinuousClearingAuctionFactory.sol`](../src/ContinuousClearingAuctionFactory.sol) | 75 lines. Not the production path, but it **is** your testnet/local path (see §4). |
| **Local dev harness** | [`dev/dev-up.sh`](../dev/dev-up.sh), [`script/deploy/DeployLocalCCA.s.sol`](../script/deploy/DeployLocalCCA.s.sol), [`LocalDevEnvironment.md`](./LocalDevEnvironment.md) | The fastest way to *feel* the mechanism: a genesis-shaped 300-block auction on Anvil with a manifest for the frontend. |

### Tier 3 — nice to understand (skim, or read on demand)

| What | Where | Why it's deprioritized |
| --- | --- | --- |
| Validation hooks periphery | [`src/periphery/validationHooks/`](../src/periphery/validationHooks) | Optional pre-bid ERC-1155 gating. They check ownership and revert; they do **not** mint receipts. Genesis can run with `validationHook = address(0)`. |
| `MaxBidPriceLib` | [`src/libraries/MaxBidPriceLib.sol`](../src/libraries/MaxBidPriceLib.sol) | Derives the price ceiling from total supply. Trust the invariant, read the derivation later. |
| `CurrencyLibrary` | [`src/libraries/CurrencyLibrary.sol`](../src/libraries/CurrencyLibrary.sol) | ETH vs ERC-20/Permit2 transfer plumbing. Genesis is ETH-only, so half of it is dead code for you. |
| LBP / protocol-fee plumbing | `lbpInitializationParams()`, `ProtocolFeeLib`, liquidity-launcher deps | **Dead paths for Astrea**: fee controller is `address(0)`, no LP migration. Kept for upstream compatibility. Know they exist and are disarmed; don't study them. |
| `CheckpointLib`, `ValidationHookLib`, `ValueX7Lib` internals | [`src/libraries/`](../src/libraries) | Thin helpers; read at call sites when needed. |
| `PlaygroundBidLens` | [`script/deploy/PlaygroundBidLens.sol`](../script/deploy/PlaygroundBidLens.sol) | Dev-only bid-outcome previewer (computes `exitPartiallyFilledBid` hints). Never deploy to a real network. |
| Upstream test suite | `test/` (BTT, fuzz, invariant) | Audited-code coverage. Use as reference for behavior questions, not as reading material. |

## 3. What changed vs upstream, and how to verify it

### The branch, commit by commit

```bash
git log --oneline main..HEAD
```

| Commit | What it is |
| --- | --- |
| `0fc1703` feat: add astrea genesis auction factory | **The production change.** Factory + interface. |
| `4ea0921` test: cover astrea genesis auction guardrails | The 10-test executable spec. |
| `5128b60` + `0068790` docs: deployment | Deployment guide + verification steps. |
| `3bf4524` chore: from gitmodules to soldeer | Dependency management swap (`lib/` submodules → `dependencies/` + `soldeer.lock`). Explains the 2-line import-path diffs across `test/btt/`. No logic change. |
| `3f6d5d2` + `306d7d6` + `3504f27` + `4380c25` feat/fix: local dev env | Anvil harness, `DeployLocalCCA`, `PlaygroundBidLens`, phase windows. All off-chain/dev-only. |
| `3614a01` + `e8f6189` docs | Local dev docs. |

### Guardrail → code → test traceability

This is your "compare what I understood with what actually exists" table. Each row: the claimed
guardrail, where it's enforced, and the test that proves it.

| Claim | Enforced at ([`AstreaGenesisAuctionFactory.sol`](../src/AstreaGenesisAuctionFactory.sol)) | Proven by (test in [`AstreaGenesisAuctionFactory.t.sol`](../test/AstreaGenesisAuctionFactory.t.sol)) |
| --- | --- | --- |
| Mainnet only | `_validateGenesisConfig`: `block.chainid != 1` reverts (line 119) | `test_create_revertsWhenNotEthereumMainnet` |
| ETH bids only | `currency: address(0)` (line 101) | `test_create_buildsAstreaGenesisAuctionParameters` |
| 7 days = 50,400 blocks | `endBlock = startBlock + 50_400` (line 99) | `test_genesisAuctionStepsData_isSevenDaysAndSumsToFullSupply` |
| Schedule sells exactly 100% | `199×20,800 + 198×29,600 = 10,000,000 MPS` (constants, lines 26–30) | same test |
| Allocation is exactly 10% | `tokenAllocation * 10 == token.totalSupply()` (line 142) | `test_create_revertsWhenAllocationIsNotTenPercentOfTokenSupply` |
| No minimum raise | `requiredCurrencyRaised: 0` (line 110) | `test_noBidFinalizationGraduatesAndSweepsAllUnsoldTokens` |
| No protocol fee | `address(0)` as 4th constructor arg (line 43) | `test_undersubscribedAuctionSettlesAndSweepsGrossEthWithoutFee` |
| Claims open at auction end | `claimBlock: endBlock` (line 106) | `test_create_buildsAstreaGenesisAuctionParameters` |
| Hook is optional passthrough | `validationHook: config.validationHook` (line 108) | `test_optionalValidationHookIsRetainedAsBidGate` |
| Recipients / start block sane | zero-address + future-block checks (lines 126–133) | `test_create_revertsWhenRecipientIsZero`, `test_create_revertsWhenStartBlockIsNotFuture` |
| Oversubscription refunds work | inherited engine behavior | `test_oversubscribedAuctionPartiallyFillsAndRefundsExcessEth` |

### Run the verification yourself

```bash
# 1. Core engine untouched (2 added files, 0 modified):
git diff main...HEAD --stat -- src/

# 2. Full suite minus fuzz/invariant (fast — ~30s; last verified 2026-07-09: 394 passed, 0 failed):
FOUNDRY_FUZZ_RUNS=8 forge test --no-match-test '[fF]uzz' --no-match-contract 'Invariant'

# 3. Just the Astrea spec:
forge test --match-contract AstreaGenesisAuctionFactory -vv

# 4. Schedule math sanity:
python3 -c "print(199*20800 + 198*29600 == 10_000_000, 20800+29600 == 50_400)"
```

Skip the fuzz/invariant suites during iteration — they take forever and cover the *inherited*
engine, which this branch doesn't modify. Run them once before a release candidate, not daily.

## 4. Path to testnet

**The blocker you need to know up front:** both the factory
([`AstreaGenesisAuctionFactory.sol:119`](../src/AstreaGenesisAuctionFactory.sol)) and its deploy
script ([`DeployAstreaGenesisAuctionFactory.s.sol:18`](../script/deploy/DeployAstreaGenesisAuctionFactory.s.sol))
hard-revert unless `block.chainid == 1`. That is deliberate — the guarded factory *is* the
mainnet-only guarantee. You cannot and should not deploy it to Sepolia as-is.

**Recommended testnet approach — mirror the local harness:** deploy the generic
`ContinuousClearingAuctionFactory` with `protocolFeeController = address(0)` and pass
genesis-shaped `AuctionParameters` yourself. This is exactly what
[`DeployLocalCCA.s.sol`](../script/deploy/DeployLocalCCA.s.sol) already does on Anvil — adapt it
into a `DeployTestnetCCA.s.sol` with a testnet RPC and a mock ERC-20. You are then testing the
*same auction bytecode* mainnet will run, just parameterized by hand.

Decisions to make for the testnet script:

- **Duration:** full 50,400 blocks (≈7 days on Sepolia's 12s blocks, realistic rehearsal) or the
  scaled 300-block schedule from the local script (fast iteration). Do a scaled one first.
- **Keep the parameter shape identical** to the factory's output: ETH currency, `requiredCurrencyRaised = 0`,
  `claimBlock = endBlock`, two-step front-loaded schedule summing to `1e7` MPS.
- Deploy `CCALens` alongside ([`DeployCCALens.s.sol`](../script/deploy/DeployCCALens.s.sol) exists).
- Do **not** deploy `PlaygroundBidLens` anywhere public.

If you want to rehearse the factory itself end-to-end (guardrails included), do it on a mainnet
fork: `anvil --fork-url $MAINNET_RPC_URL` reports chain id 1, so `create()` works unmodified.
Avoid the tempting hack of relaxing the chain-id constant "just for testnet" — that turns your
rehearsal into a test of code that will never ship.

The operational sequence (same on testnet as mainnet — see [`DeploymentGuide.md`](./DeploymentGuide.md)):

```
deploy factory (or generic factory + params) → getAddress() to predict → create()
→ transfer exactly tokenAllocation to the auction → onTokensReceived()
→ verify: token(), currency() == 0x0, totalSupply(), startBlock/endBlock/claimBlock,
  isGraduated() == true (zero threshold), validationHook()
→ publish addresses/ABIs to frontend + indexer BEFORE startBlock
```

## 5. Frontend integration

Rehearse locally first — this loop is the fastest teacher in the repo:

```bash
./dev/dev-up.sh     # Anvil + full CCA stack + deployments/local.json manifest
./dev/dev-down.sh   # teardown
```

It writes `deployments/local.json` (chainId, rpcUrl, token/factory/auction/lens addresses, phase
blocks). The companion [cca-playground](https://github.com/astrea-foundation/cca-playground) repo
consumes that manifest plus ABIs from `out/` — it's a working reference frontend (tick ladder,
bids, time travel). `START_DELAY`/`CLAIM_DELAY` env vars give you distinct pre-genesis and
settlement windows to build UI states against.

What a frontend needs, in order:

1. **Reads — go through `CCALens`, not raw views.** Raw `clearingPrice()` is stale between
   checkpoints; `lens.state(auction)` simulates a checkpoint in an `eth_call` and returns fresh
   `Checkpoint`, `currencyRaised`, `totalCleared`, `isGraduated`. `getInitializedTickData(auction)`
   gives the tick ladder with "currency needed to lift price to this tick" per tick — that's your
   order-book visualization, precomputed.
2. **Writes:** `submitBid(maxPrice, amount, owner, prevTickPrice, hookData)` — ETH goes in
   `msg.value`; compute `prevTickPrice` off-chain from lens data (the hintless overload does an
   on-chain linked-list walk and burns gas); `maxPrice` must be `floorPrice + k·tickSpacing`,
   strictly above current clearing, below `MAX_BID_PRICE`. After the end: `exitBid` /
   `exitPartiallyFilledBid` → `claimTokens`. **Exit before claim is mandatory.**
3. **The hard UX problem:** `exitPartiallyFilledBid` needs two checkpoint-block hints
   (`lastFullyFilledCheckpointBlock`, `outbidBlock`). Your frontend/indexer must reconstruct
   these from `CheckpointUpdated` events. Locally, `PlaygroundBidLens` computes them for you —
   study its logic, reimplement off-chain, don't ship it.
4. **Events to index:** `BidSubmitted`, `TickInitialized`, `CheckpointUpdated`,
   `ClearingPriceUpdated`, `BidExited`, `TokensClaimed`, `CurrencySwept`, `TokensSwept`
   (all in [`IContinuousClearingAuction.sol`](../src/interfaces/IContinuousClearingAuction.sol)).
5. **Phases** (drive all UI state off block numbers): pre-genesis (`block < startBlock`, funded +
   verified, no bids) → live (bids, ratcheting price) → since `claimBlock == endBlock`, settlement
   actions (exit, claim, sweeps) all open at `endBlock`.

## 6. Sharp edges (each one has cost someone real pain)

- **Lazy state.** Nothing self-updates. If no one bids, no one checkpoints. Have a keeper (or a
  cron'd `checkpoint()` call) during the live window, and always read through the lens.
- **Q96 everywhere.** `floorPrice` and `tickSpacing` are Q96 currency-wei per token-wei. A raw
  "0.1 ETH" where a Q96 value belongs is off by 2^96. See `DeployLocalCCA.s.sol` for correct examples.
- **Funding is exact and unforgiving.** Transfer *exactly* `tokenAllocation`, then call
  `onTokensReceived()`. Extra tokens or ETH sent directly to the auction are unrecoverable. Bids
  revert until `onTokensReceived()` succeeds.
- **`prevTickPrice` hint or gas bomb.** The hintless `submitBid` overload walks the whole tick
  list on-chain.
- **Graduation is a no-op here — almost.** `requiredCurrencyRaised = 0` means always graduated,
  no failure path. But `sweepUnsoldTokens()` behavior still branches on graduation upstream —
  Astrea always takes the graduated branch (`remainingSupply()`, not `totalSupply`).
- **Sweeps are one-shot and gated:** `sweepCurrency()` only by `fundsRecipient`, `sweepUnsoldTokens()`
  only by `tokensRecipient`, both only after end + final checkpoint. Second call reverts.
- **Rounding dust.** `totalCleared` rounds up intentionally; a few wei of token can be permanently
  stuck. Expected, not a bug.
- **Checkpoint semantics:** at most one per block, and it snapshots state up to but *not including*
  its block. Off-by-one bugs in indexers come from ignoring this.
- **`test_` naming lies a little:** some upstream "unit" tests are parameterized fuzz tests. Use
  the `--no-match-test '[fF]uzz' --no-match-contract 'Invariant'` filter from §3 for a fast loop.
