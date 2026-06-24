// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDistributorFactory} from 'liquidity-launcher/src/interfaces/IDistributorFactory.sol';

/// @notice Factory-specific parameters for the Astrea Genesis Auction.
/// @dev ETH currency, zero graduation threshold, claim block, and schedule are fixed by the factory.
struct AstreaGenesisAuctionConfig {
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint256 floorPrice;
    uint256 tickSpacing;
    address validationHook;
}

/// @title IAstreaGenesisAuctionFactory
interface IAstreaGenesisAuctionFactory is IDistributorFactory {
    error AstreaGenesisAuctionFactory__InvalidChain(uint256 chainId);
    error AstreaGenesisAuctionFactory__TokenIsAddressZero();
    error AstreaGenesisAuctionFactory__InvalidTokenAmount(uint256 tokenAllocation);
    error AstreaGenesisAuctionFactory__InvalidTokenAllocation(uint256 tokenAllocation, uint256 tokenTotalSupply);
    error AstreaGenesisAuctionFactory__TokensRecipientIsZero();
    error AstreaGenesisAuctionFactory__FundsRecipientIsZero();
    error AstreaGenesisAuctionFactory__StartBlockNotFuture(uint64 startBlock, uint256 currentBlock);
    error AstreaGenesisAuctionFactory__StartBlockTooLate(uint64 startBlock);
    error AstreaGenesisAuctionFactory__FloorPriceTooLow(uint256 floorPrice);
    error AstreaGenesisAuctionFactory__TickSpacingTooSmall(uint256 tickSpacing);

    event AstreaGenesisAuctionCreated(
        address indexed auction,
        address indexed token,
        uint256 tokenAllocation,
        address tokensRecipient,
        address fundsRecipient,
        uint64 startBlock,
        uint64 endBlock,
        uint256 floorPrice,
        uint256 tickSpacing,
        address validationHook
    );

    /// @notice Returns the packed two-step 7-day Ethereum mainnet Genesis Auction schedule.
    function genesisAuctionStepsData() external pure returns (bytes memory);
}
