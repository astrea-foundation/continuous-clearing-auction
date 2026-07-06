# Astrea Genesis Auction

This repository is Astrea's guarded fork of Uniswap's Continuous Clearing Auction (CCA) contracts for the ASTREA Genesis Auction on Ethereum mainnet.

The fork keeps the audited CCA auction accounting, bidding, checkpointing, exits, claims, sweeps, lenses, and optional validation-hook plumbing intact. Astrea-specific behavior is enforced through a separate production factory and deployment documentation.

## Genesis Auction v1

The v1 production path is [`AstreaGenesisAuctionFactory`](./src/AstreaGenesisAuctionFactory.sol). It deploys unmodified [`ContinuousClearingAuction`](./src/ContinuousClearingAuction.sol) instances with these guardrails:

- Ethereum mainnet only.
- ETH bids only.
- 7-day auction duration, represented as 50,400 Ethereum blocks.
- 10% token allocation, checked against the token's `totalSupply()`.
- `requiredCurrencyRaised = 0`, so there is no minimum raise failure condition.
- No protocol fee controller.
- No automatic LP migration.
- Optional pre-bid validation hook support.

The ERC-1155 validation hooks under [`src/periphery/validationHooks`](./src/periphery/validationHooks) are optional gating periphery. They check existing ERC-1155 ownership before a bid is accepted; they do not mint participation receipts.

The Genesis Participation NFT is intentionally deferred to a later dedicated implementation.

## Development

```bash
forge soldeer install
forge build
forge test
```

The repository uses Foundry with optimizer settings in [`foundry.toml`](./foundry.toml). Tests include the upstream CCA unit, fuzz, and invariant suite plus Astrea-specific factory and settlement guardrail coverage.

## Deployment

Use the Astrea factory deployment path for production Genesis Auction deployments:

- [Deployment guide](./docs/DeploymentGuide.md)
- [Astrea Genesis Auction plan](./docs/astrea-PLAN-v1.md)
- [Astrea Genesis Auction product brief](./docs/Astrea%20ICO%20-%20Genesis%20Auction%20%28CCA%20Fork%29.md)

The generic [`ContinuousClearingAuctionFactory`](./src/ContinuousClearingAuctionFactory.sol) remains in the repository for upstream compatibility and tests, but it is not the Astrea Genesis Auction production path.

## Local dev / test environment

To run the auction end to end on a local Anvil chain, see the
[Local Dev Environment guide](./docs/LocalDevEnvironment.md):

```bash
./dev/dev-up.sh   # start Anvil, deploy the CCA stack, write deployments/local.json
```

A companion web console (live state, tick ladder, simulated ETH bids) lives in the
separate [cca-playground](https://github.com/astrea-foundation/cca-playground) repository,
which consumes this repo's deployment manifest and ABIs.

## Documentation

- [Technical documentation](./docs/TechnicalDocumentation.md)
- [Deployment guide](./docs/DeploymentGuide.md)
- [Local dev / test environment](./docs/LocalDevEnvironment.md)
- [Changelog](./CHANGELOG.md)

## Audit Provenance

The underlying CCA codebase has upstream audit reports from Spearbit, OpenZeppelin, and ABDK Consulting in [`docs/audits`](./docs/audits). These reports are provenance for the inherited Uniswap CCA code. Astrea-specific factory, deployment, and documentation changes need separate review before mainnet use.

## License

The contracts are covered under the MIT License. See [`LICENSE`](./LICENSE).
