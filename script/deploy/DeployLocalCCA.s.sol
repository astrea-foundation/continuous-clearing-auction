// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionStepsBuilder} from '../../test/utils/AuctionStepsBuilder.sol';
import {PlaygroundBidLens} from './PlaygroundBidLens.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ContinuousClearingAuctionFactory} from 'continuous-clearing-auction/ContinuousClearingAuctionFactory.sol';
import {AuctionParameters} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {CCALens} from 'continuous-clearing-auction/lens/CCALens.sol';
import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

/// @notice Minimal mintable ERC20 used as the local "ASTREA" token for the dev/test auction.
/// @dev This is a local-only mock. Production uses the real ASTREA token on Ethereum mainnet.
contract AstreaLocalToken is ERC20 {
    constructor(uint256 _initialSupply, address _to) ERC20('Astrea (Local Dev)', 'ASTREA') {
        _mint(_to, _initialSupply);
    }
}

/// @title DeployLocalCCAScript
/// @notice Deploys a full Continuous Clearing Auction stack to a local Anvil chain for dev/test/visualization.
/// @dev Mirrors the Astrea Genesis Auction shape (ETH-only bids, zero graduation threshold, front-loaded
///      two-step MPS schedule) but scales the token supply and block duration down so the auction is
///      interactive on a local chain. Not for production — production uses AstreaGenesisAuctionFactory on mainnet.
contract DeployLocalCCAScript is Script {
    using AuctionStepsBuilder for bytes;

    // --- Genesis-shaped price granularity (Q96) ---
    // floorPrice = 100 * tickSpacing ≈ 0.1 ETH per token; tickSpacing ≈ 0.001 ETH per token.
    uint256 internal constant FLOOR_PRICE_Q96 = 7_922_816_251_426_433_759_354_395_000;
    uint256 internal constant TICK_SPACING_Q96 = 79_228_162_514_264_337_593_543_950;

    // --- Scaled-down token economics ---
    // 10,000 ASTREA total minted; 10% (1,000 ASTREA) allocated to the auction, matching the genesis 10% narrative.
    uint256 internal constant TOTAL_MINT = 10_000 ether;
    uint128 internal constant AUCTION_ALLOCATION = 1000 ether;

    // --- Scaled-down schedule: front-loaded two steps, 300 blocks total, sum(mps*blocks) == 1e7 ---
    uint24 internal constant STEP1_MPS = 50_000; // fast release
    uint40 internal constant STEP1_BLOCKS = 100;
    uint24 internal constant STEP2_MPS = 25_000; // slow release
    uint40 internal constant STEP2_BLOCKS = 200;

    function run()
        public
        returns (AstreaLocalToken token, ContinuousClearingAuctionFactory factory, address auction, CCALens lens)
    {
        // Recipients default to the broadcasting deployer so sweeps can be exercised from the dev account.
        address deployer = msg.sender;
        address tokensRecipient = vm.envOr('TOKENS_RECIPIENT', deployer);
        address fundsRecipient = vm.envOr('FUNDS_RECIPIENT', deployer);
        // Number of blocks after the current block at which the auction opens.
        uint64 startDelay = uint64(vm.envOr('START_DELAY', uint256(1)));
        // Number of blocks after the end block before claims open, so the settlement
        // window (ended, claims not yet open) exists as a distinct phase locally.
        uint64 claimDelay = uint64(vm.envOr('CLAIM_DELAY', uint256(50)));

        uint64 startBlock = uint64(block.number) + startDelay;
        uint64 endBlock = startBlock + uint64(STEP1_BLOCKS) + uint64(STEP2_BLOCKS);
        uint64 claimBlock = endBlock + claimDelay;

        bytes memory stepsData =
            AuctionStepsBuilder.init().addStep(STEP1_MPS, STEP1_BLOCKS).addStep(STEP2_MPS, STEP2_BLOCKS);

        AuctionParameters memory params = AuctionParameters({
            currency: address(0), // ETH
            tokensRecipient: tokensRecipient,
            fundsRecipient: fundsRecipient,
            startBlock: startBlock,
            endBlock: endBlock,
            claimBlock: claimBlock,
            tickSpacing: TICK_SPACING_Q96,
            validationHook: address(0),
            floorPrice: FLOOR_PRICE_Q96,
            requiredCurrencyRaised: 0, // graduates unconditionally, like genesis
            auctionStepsData: stepsData
        });

        vm.startBroadcast();

        // 1. Deploy the local ASTREA token and mint the full supply to the deployer.
        token = new AstreaLocalToken(TOTAL_MINT, deployer);

        // 2. Deploy the generic auction factory with no protocol fee controller.
        factory = new ContinuousClearingAuctionFactory(address(0));

        // 3. Create the auction through the factory.
        auction = address(factory.create(address(token), AUCTION_ALLOCATION, abi.encode(params), bytes32(0)));

        // 4. Fund the auction with the allocation and notify it.
        token.transfer(auction, AUCTION_ALLOCATION);
        (bool ok,) = auction.call(abi.encodeWithSignature('onTokensReceived()'));
        require(ok, 'onTokensReceived failed');

        // 5. Deploy the read-only lens (batched state reads for offchain consumers).
        lens = new CCALens();

        // 6. Deploy the dev-only bid-outcome lens used by the cca-playground UI.
        PlaygroundBidLens bidLens = new PlaygroundBidLens();

        vm.stopBroadcast();

        _logAndWrite(token, factory, auction, lens, address(bidLens), startBlock, endBlock, claimBlock);
    }

    function _logAndWrite(
        AstreaLocalToken token,
        ContinuousClearingAuctionFactory factory,
        address auction,
        CCALens lens,
        address bidLens,
        uint64 startBlock,
        uint64 endBlock,
        uint64 claimBlock
    ) internal {
        console2.log('ASTREA token:      ', address(token));
        console2.log('Auction factory:   ', address(factory));
        console2.log('CCA auction:       ', auction);
        console2.log('CCA lens:          ', address(lens));
        console2.log('Bid lens (dev):    ', bidLens);
        console2.log('Start block:       ', startBlock);
        console2.log('End block:         ', endBlock);
        console2.log('Claim block:       ', claimBlock);

        // Write a deployment manifest for offchain consumers (e.g. the cca-playground console).
        // Built in two concats to stay within stack limits.
        string memory addresses = string.concat(
            '{\n',
            '  "chainId": ',
            vm.toString(block.chainid),
            ',\n',
            '  "rpcUrl": "http://127.0.0.1:8545",\n',
            '  "token": "',
            vm.toString(address(token)),
            '",\n',
            '  "factory": "',
            vm.toString(address(factory)),
            '",\n',
            '  "auction": "',
            vm.toString(auction),
            '",\n',
            '  "lens": "',
            vm.toString(address(lens)),
            '",\n',
            '  "bidLens": "',
            vm.toString(bidLens),
            '",\n'
        );
        string memory blocks = string.concat(
            '  "startBlock": ',
            vm.toString(startBlock),
            ',\n',
            '  "endBlock": ',
            vm.toString(endBlock),
            ',\n',
            '  "claimBlock": ',
            vm.toString(claimBlock),
            '\n}\n'
        );
        vm.writeFile('./deployments/local.json', string.concat(addresses, blocks));
        console2.log('Wrote deployments/local.json');
    }
}
