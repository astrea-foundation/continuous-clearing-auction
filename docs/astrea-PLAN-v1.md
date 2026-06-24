# Astrea Genesis CCA Fork Plan

## Summary
- Build v1 as a guarded fork: keep audited CCA auction accounting, bid, exit, claim, sweep, checkpoint, tick, lens, and validation-hook plumbing intact.
- Astrea-specific behavior is enforced through deployment guardrails and docs: ETH only, 7-day Ethereum mainnet auction, 10% token allocation supplied at deploy time, `requiredCurrencyRaised = 0`, no protocol fee, no LP migration.
- Keep Uniswap’s ERC-1155 validation hooks, but classify them as optional pre-bid gating infrastructure, not participation receipts.
- Defer the Genesis Participation NFT to a later dedicated goal.

## Source Changes
- Add an Astrea production factory/deployment path that constructs `AuctionParameters` internally and rejects invalid production config.
- Preserve `ContinuousClearingAuction` core behavior unless a later review finds an unavoidable Astrea requirement.
- Keep `BaseERC1155ValidationHook` and `GatedERC1155ValidationHook`; update docs to explain they check existing NFT ownership before bidding.
- Do not add receipt NFT minting in v1. Later receipt NFT should be a separate contract that reads `bids(bidId)` and lets users claim/mint proof of participation.

## Tests
- Preserve upstream CCA tests for settlement, exits, claims, checkpoints, ticks, sweeps, hooks, and invariants.
- Add Astrea tests for ETH-only config, zero graduation threshold, no protocol fee, 7-day schedule, recipient permissions, no-bid finalization, undersubscribed auction, and oversubscribed fills/refunds.
- Keep ERC-1155 hook tests, but rename/reframe them as optional gating tests.

## Docs And Cleanup
- Rewrite README, technical docs, deployment guide, and example config around Astrea Genesis Auction.
- Remove or relabel Uniswap canonical deployment addresses, Liquidity Launcher positioning, bug bounty language, and stale generated docs.
- Keep upstream audit PDFs as provenance only; state clearly that Astrea changes need separate review.
- Add a receipt NFT section explaining that the current ERC-1155 hooks do not mint receipts and that receipt NFT work is deferred.

## Assumptions
- No onchain FDV cap is implemented until Astrea finalizes the cap.
- NFT receipt is out of v1 implementation scope.
- ERC-1155 hooks remain because they may be useful for future gated participation or NFT-related research.
