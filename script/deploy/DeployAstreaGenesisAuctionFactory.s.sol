// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AstreaGenesisAuctionFactory} from 'continuous-clearing-auction/AstreaGenesisAuctionFactory.sol';
import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

/// @title DeployAstreaGenesisAuctionFactoryScript
/// @notice Deploys the guarded Astrea Genesis Auction factory on Ethereum mainnet.
contract DeployAstreaGenesisAuctionFactoryScript is Script {
    uint256 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;
    bytes32 internal constant ASTREA_GENESIS_FACTORY_SALT =
        0x18dca24429711d7603e45c2e6a8d84f654f56006a8e3cff18c90d7fc0a5ea001;

    error DeployAstreaGenesisAuctionFactoryScript__InvalidChain(uint256 chainId);

    function run() public returns (AstreaGenesisAuctionFactory factory) {
        if (block.chainid != ETHEREUM_MAINNET_CHAIN_ID) {
            revert DeployAstreaGenesisAuctionFactoryScript__InvalidChain(block.chainid);
        }

        vm.startBroadcast();
        factory = new AstreaGenesisAuctionFactory{salt: ASTREA_GENESIS_FACTORY_SALT}();
        vm.stopBroadcast();

        console2.log('AstreaGenesisAuctionFactory deployed to:', address(factory));
    }
}
