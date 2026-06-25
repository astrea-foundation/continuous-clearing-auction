# Astrea Genesis Auction Deployment Guide

This guide covers the guarded Astrea Genesis Auction v1 path. It does not use the generic CCA factory or Liquidity Launcher migration flow.

## Production Shape

The production factory is [`AstreaGenesisAuctionFactory`](../src/AstreaGenesisAuctionFactory.sol). It deploys a standard [`ContinuousClearingAuction`](../src/ContinuousClearingAuction.sol) with Astrea parameters constructed internally:

- `currency = address(0)` for ETH-only bidding.
- `requiredCurrencyRaised = 0`.
- `protocolFeeController = address(0)`.
- `endBlock = startBlock + 50,400`.
- `claimBlock = endBlock`.
- `auctionStepsData` is the fixed two-step 7-day schedule returned by `genesisAuctionStepsData()`.

The caller supplies only:

```solidity
struct AstreaGenesisAuctionConfig {
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint256 floorPrice;
    uint256 tickSpacing;
    address validationHook;
}
```

The factory rejects non-mainnet deployments, zero recipients, a non-future start block, invalid price granularity, and any `tokenAllocation` that is not exactly 10% of the token's `totalSupply()`.

## 1. Preflight

Confirm these values before deployment:

- ASTREA token address.
- ASTREA total supply has been minted and `tokenAllocation * 10 == token.totalSupply()`.
- Token allocation amount for the auction.
- Treasury `fundsRecipient`.
- Unsold-token `tokensRecipient`.
- Auction `startBlock`.
- Q96 `floorPrice` and `tickSpacing`.
- Optional validation hook address, or `address(0)` for no bid gate.

The start block must leave enough time to create the auction, transfer tokens into it, call `onTokensReceived()`, verify state, and publish frontend/indexer configuration before bidding opens.

## 2. Deploy Factory

Use Foundry account management instead of plaintext private keys.

```bash
forge script script/deploy/DeployAstreaGenesisAuctionFactory.s.sol:DeployAstreaGenesisAuctionFactoryScript \
  --rpc-url $MAINNET_RPC_URL \
  --account $DEPLOYER_ACCOUNT \
  --sender $DEPLOYER_ADDRESS \
  --broadcast \
  --verify --verifier etherscan \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

The script reverts unless `block.chainid == 1`.

## 3. Create Auction

Encode `AstreaGenesisAuctionConfig` and call:

```solidity
function create(
    address token,
    uint256 tokenAllocation,
    bytes calldata configData,
    bytes32 salt
) external returns (IDistributor auction);
```

Use `getAddress(token, tokenAllocation, configData, salt, sender)` before sending the transaction to confirm the expected CREATE2 address.

An example configuration shape is in [`script/astrea-genesis.example.json`](../script/astrea-genesis.example.json). Treat it as an operator checklist, not a source of truth.

## 4. Fund Auction

After the auction is created and before `startBlock`:

1. Transfer exactly `tokenAllocation` ASTREA to the auction address.
2. Call `onTokensReceived()` on the auction.
3. Verify:
   - `token() == ASTREA token`.
   - `currency() == address(0)`.
   - `totalSupply() == tokenAllocation`.
   - `startBlock()`, `endBlock()`, and `claimBlock()` match expectations.
   - `isGraduated() == true` because the threshold is zero.
   - `validationHook()` is either the approved hook or `address(0)`.

Bids are rejected until `onTokensReceived()` has succeeded.

## 5. During Auction

Participants submit ETH bids through `submitBid`. Optional ERC-1155 validation hooks only gate bid eligibility; they do not mint NFTs or receipts.

State updates are lazy. Operators or keepers may call `checkpoint()` and, if needed, `forceIterateOverTicks()` to keep the clearing price current for frontends.

## 6. Finalization

At or after `endBlock`:

1. Call `checkpoint()` to finalize the auction state.
2. Bidders exit their bids with `exitBid()` or `exitPartiallyFilledBid()`.
3. Bidders claim ASTREA with `claimTokens()` or `claimTokensBatch()`.
4. `fundsRecipient` calls `sweepCurrency()` to receive raised ETH.
5. `tokensRecipient` calls `sweepUnsoldTokens()` to receive unsold ASTREA.

Because `requiredCurrencyRaised = 0`, a no-bid auction still graduates. In that case `totalCleared() == 0`, `currencyRaised() == 0`, and `sweepUnsoldTokens()` returns the full auction allocation.

## 7. Verification

Verify the factory and auction contracts on the block explorer using Foundry standard JSON output:

```bash
forge verify-contract <factory_address> src/AstreaGenesisAuctionFactory.sol:AstreaGenesisAuctionFactory \
  --rpc-url $MAINNET_RPC_URL \
  --show-standard-json-input > astrea-factory-standard-json-input.json

forge verify-contract <auction_address> src/ContinuousClearingAuction.sol:ContinuousClearingAuction \
  --rpc-url $MAINNET_RPC_URL \
  --show-standard-json-input > astrea-auction-standard-json-input.json
```

The auction constructor arguments are `token`, `tokenAllocation`, the internally constructed `AuctionParameters`, and `address(0)` for the protocol fee controller.
