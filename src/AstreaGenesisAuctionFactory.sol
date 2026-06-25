// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {ContinuousClearingAuction} from 'continuous-clearing-auction/ContinuousClearingAuction.sol';
import {
    AstreaGenesisAuctionConfig,
    IAstreaGenesisAuctionFactory
} from 'continuous-clearing-auction/interfaces/IAstreaGenesisAuctionFactory.sol';
import {AuctionParameters} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {IDistributor} from 'liquidity-launcher/src/interfaces/IDistributor.sol';
import {IDistributorFactory} from 'liquidity-launcher/src/interfaces/IDistributorFactory.sol';

interface IERC20TotalSupply {
    function totalSupply() external view returns (uint256);
}

/// @title AstreaGenesisAuctionFactory
/// @notice Production factory for the Ethereum mainnet ASTREA Genesis Auction.
/// @dev Deploys unmodified ContinuousClearingAuction instances with Astrea-specific guardrails.
/// @custom:security-contact security@astrea.xyz
contract AstreaGenesisAuctionFactory is IAstreaGenesisAuctionFactory {
    uint256 public constant ETHEREUM_MAINNET_CHAIN_ID = 1;
    uint256 public constant GENESIS_TOKEN_ALLOCATION_DENOMINATOR = 10;
    uint40 public constant GENESIS_AUCTION_DURATION_BLOCKS = 50_400;
    uint40 public constant GENESIS_AUCTION_HIGH_MPS_BLOCKS = 20_800;
    uint40 public constant GENESIS_AUCTION_LOW_MPS_BLOCKS = 29_600;
    uint24 public constant GENESIS_AUCTION_HIGH_MPS = 199;
    uint24 public constant GENESIS_AUCTION_LOW_MPS = 198;

    /// @inheritdoc IDistributorFactory
    function create(address token, uint256 tokenAllocation, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributor distributor)
    {
        AstreaGenesisAuctionConfig memory config = abi.decode(configData, (AstreaGenesisAuctionConfig));
        AuctionParameters memory parameters = _auctionParameters(token, tokenAllocation, config);

        distributor = IDistributor(
            address(
                new ContinuousClearingAuction{salt: keccak256(abi.encode(msg.sender, salt))}(
                    token, uint128(tokenAllocation), parameters, address(0)
                )
            )
        );

        emit AstreaGenesisAuctionCreated(
            address(distributor),
            token,
            tokenAllocation,
            config.tokensRecipient,
            config.fundsRecipient,
            config.startBlock,
            parameters.endBlock,
            config.floorPrice,
            config.tickSpacing,
            config.validationHook
        );
    }

    /// @inheritdoc IDistributorFactory
    function getAddress(address token, uint256 tokenAllocation, bytes calldata configData, bytes32 salt, address sender)
        external
        view
        returns (IDistributor distributor)
    {
        AstreaGenesisAuctionConfig memory config = abi.decode(configData, (AstreaGenesisAuctionConfig));
        AuctionParameters memory parameters = _auctionParameters(token, tokenAllocation, config);

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(ContinuousClearingAuction).creationCode,
                abi.encode(token, uint128(tokenAllocation), parameters, address(0))
            )
        );

        distributor =
            IDistributor(Create2.computeAddress(keccak256(abi.encode(sender, salt)), initCodeHash, address(this)));
    }

    /// @inheritdoc IAstreaGenesisAuctionFactory
    function genesisAuctionStepsData() public pure returns (bytes memory) {
        return abi.encodePacked(
            GENESIS_AUCTION_HIGH_MPS,
            GENESIS_AUCTION_HIGH_MPS_BLOCKS,
            GENESIS_AUCTION_LOW_MPS,
            GENESIS_AUCTION_LOW_MPS_BLOCKS
        );
    }

    function _auctionParameters(address token, uint256 tokenAllocation, AstreaGenesisAuctionConfig memory config)
        internal
        view
        returns (AuctionParameters memory parameters)
    {
        _validateGenesisConfig(token, tokenAllocation, config);

        uint64 endBlock = config.startBlock + uint64(GENESIS_AUCTION_DURATION_BLOCKS);
        parameters = AuctionParameters({
            currency: address(0),
            tokensRecipient: config.tokensRecipient,
            fundsRecipient: config.fundsRecipient,
            startBlock: config.startBlock,
            endBlock: endBlock,
            claimBlock: endBlock,
            tickSpacing: config.tickSpacing,
            validationHook: config.validationHook,
            floorPrice: config.floorPrice,
            requiredCurrencyRaised: 0,
            auctionStepsData: genesisAuctionStepsData()
        });
    }

    function _validateGenesisConfig(address token, uint256 tokenAllocation, AstreaGenesisAuctionConfig memory config)
        internal
        view
    {
        if (block.chainid != ETHEREUM_MAINNET_CHAIN_ID) {
            revert AstreaGenesisAuctionFactory__InvalidChain(block.chainid);
        }
        if (token == address(0)) revert AstreaGenesisAuctionFactory__TokenIsAddressZero();
        if (tokenAllocation == 0 || tokenAllocation > type(uint128).max) {
            revert AstreaGenesisAuctionFactory__InvalidTokenAmount(tokenAllocation);
        }
        if (config.tokensRecipient == address(0)) revert AstreaGenesisAuctionFactory__TokensRecipientIsZero();
        if (config.fundsRecipient == address(0)) revert AstreaGenesisAuctionFactory__FundsRecipientIsZero();
        if (config.startBlock <= block.number) {
            revert AstreaGenesisAuctionFactory__StartBlockNotFuture(config.startBlock, block.number);
        }
        if (config.startBlock > type(uint64).max - uint64(GENESIS_AUCTION_DURATION_BLOCKS)) {
            revert AstreaGenesisAuctionFactory__StartBlockTooLate(config.startBlock);
        }
        if (config.floorPrice < ConstantsLib.MIN_FLOOR_PRICE) {
            revert AstreaGenesisAuctionFactory__FloorPriceTooLow(config.floorPrice);
        }
        if (config.tickSpacing < ConstantsLib.MIN_TICK_SPACING) {
            revert AstreaGenesisAuctionFactory__TickSpacingTooSmall(config.tickSpacing);
        }

        uint256 tokenTotalSupply = IERC20TotalSupply(token).totalSupply();
        if (tokenAllocation * GENESIS_TOKEN_ALLOCATION_DENOMINATOR != tokenTotalSupply) {
            revert AstreaGenesisAuctionFactory__InvalidTokenAllocation(tokenAllocation, tokenTotalSupply);
        }
    }
}
