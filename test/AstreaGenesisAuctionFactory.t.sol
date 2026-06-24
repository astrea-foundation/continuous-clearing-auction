// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AstreaGenesisAuctionFactory} from 'continuous-clearing-auction/AstreaGenesisAuctionFactory.sol';
import {ContinuousClearingAuction} from 'continuous-clearing-auction/ContinuousClearingAuction.sol';
import {
    AstreaGenesisAuctionConfig,
    IAstreaGenesisAuctionFactory
} from 'continuous-clearing-auction/interfaces/IAstreaGenesisAuctionFactory.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {IValidationHook} from 'continuous-clearing-auction/interfaces/IValidationHook.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {StepLib} from 'continuous-clearing-auction/libraries/StepLib.sol';
import {Test} from 'forge-std/Test.sol';
import {IDistributor} from 'liquidity-launcher/src/interfaces/IDistributor.sol';

contract AstreaTestToken {
    string public constant name = 'Astrea Test Token';
    string public constant symbol = 'ASTREA';
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address account => uint256 balance) public balanceOf;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
        totalSupply += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract RevertingValidationHook is IValidationHook {
    error RevertingValidationHook__Rejected();

    function validate(uint256, uint128, address, address, bytes calldata) external pure {
        revert RevertingValidationHook__Rejected();
    }
}

contract AstreaGenesisAuctionFactoryTest is Test {
    using StepLib for bytes;

    uint128 internal constant AUCTION_TOKEN_ALLOCATION = 1000e18;
    uint256 internal constant ASTREA_TOTAL_SUPPLY = 10_000e18;
    uint256 internal constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 internal constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    bytes32 internal constant SALT = bytes32(uint256(1));

    AstreaGenesisAuctionFactory internal factory;
    AstreaTestToken internal token;
    AstreaGenesisAuctionConfig internal config;
    address internal alice;
    address internal fundsRecipient;
    address internal tokensRecipient;

    function setUp() public {
        vm.chainId(1);

        token = new AstreaTestToken();
        token.mint(address(this), ASTREA_TOTAL_SUPPLY);

        factory = new AstreaGenesisAuctionFactory();
        alice = makeAddr('alice');
        fundsRecipient = makeAddr('fundsRecipient');
        tokensRecipient = makeAddr('tokensRecipient');

        config = AstreaGenesisAuctionConfig({
            tokensRecipient: tokensRecipient,
            fundsRecipient: fundsRecipient,
            startBlock: uint64(block.number + 10),
            floorPrice: FLOOR_PRICE,
            tickSpacing: TICK_SPACING,
            validationHook: address(0)
        });
    }

    function test_create_buildsAstreaGenesisAuctionParameters() public {
        bytes memory configData = abi.encode(config);
        address predicted =
            address(factory.getAddress(address(token), AUCTION_TOKEN_ALLOCATION, configData, SALT, address(this)));

        uint64 expectedEndBlock = config.startBlock + uint64(factory.GENESIS_AUCTION_DURATION_BLOCKS());

        vm.expectEmit(true, true, false, true);
        emit IAstreaGenesisAuctionFactory.AstreaGenesisAuctionCreated(
            predicted,
            address(token),
            AUCTION_TOKEN_ALLOCATION,
            tokensRecipient,
            fundsRecipient,
            config.startBlock,
            expectedEndBlock,
            FLOOR_PRICE,
            TICK_SPACING,
            address(0)
        );

        ContinuousClearingAuction auction = _createAuction();

        assertEq(address(auction), predicted);
        assertEq(auction.currency(), address(0));
        assertEq(auction.token(), address(token));
        assertEq(auction.totalSupply(), AUCTION_TOKEN_ALLOCATION);
        assertEq(auction.tokensRecipient(), tokensRecipient);
        assertEq(auction.fundsRecipient(), fundsRecipient);
        assertEq(auction.startBlock(), config.startBlock);
        assertEq(auction.endBlock(), expectedEndBlock);
        assertEq(auction.claimBlock(), auction.endBlock());
        assertEq(auction.floorPrice(), FLOOR_PRICE);
        assertEq(auction.tickSpacing(), TICK_SPACING);
        assertEq(address(auction.validationHook()), address(0));
        assertTrue(auction.isGraduated());
    }

    function test_genesisAuctionStepsData_isSevenDaysAndSumsToFullSupply() public {
        bytes memory stepsData = factory.genesisAuctionStepsData();
        assertEq(stepsData.length, StepLib.UINT64_SIZE * 2);

        (uint24 highMps, uint40 highBlocks) = stepsData.get(0);
        (uint24 lowMps, uint40 lowBlocks) = stepsData.get(StepLib.UINT64_SIZE);

        assertEq(highMps, factory.GENESIS_AUCTION_HIGH_MPS());
        assertEq(highBlocks, factory.GENESIS_AUCTION_HIGH_MPS_BLOCKS());
        assertEq(lowMps, factory.GENESIS_AUCTION_LOW_MPS());
        assertEq(lowBlocks, factory.GENESIS_AUCTION_LOW_MPS_BLOCKS());
        assertEq(uint256(highBlocks) + lowBlocks, factory.GENESIS_AUCTION_DURATION_BLOCKS());
        assertEq(uint256(highMps) * highBlocks + uint256(lowMps) * lowBlocks, 10_000_000);
    }

    function test_create_revertsWhenNotEthereumMainnet() public {
        vm.chainId(31_337);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAstreaGenesisAuctionFactory.AstreaGenesisAuctionFactory__InvalidChain.selector, 31_337
            )
        );
        factory.create(address(token), AUCTION_TOKEN_ALLOCATION, abi.encode(config), SALT);
    }

    function test_create_revertsWhenAllocationIsNotTenPercentOfTokenSupply() public {
        uint256 invalidAllocation = AUCTION_TOKEN_ALLOCATION - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAstreaGenesisAuctionFactory.AstreaGenesisAuctionFactory__InvalidTokenAllocation.selector,
                invalidAllocation,
                ASTREA_TOTAL_SUPPLY
            )
        );
        factory.create(address(token), invalidAllocation, abi.encode(config), SALT);
    }

    function test_create_revertsWhenStartBlockIsNotFuture() public {
        config.startBlock = uint64(block.number);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAstreaGenesisAuctionFactory.AstreaGenesisAuctionFactory__StartBlockNotFuture.selector,
                config.startBlock,
                block.number
            )
        );
        factory.create(address(token), AUCTION_TOKEN_ALLOCATION, abi.encode(config), SALT);
    }

    function test_create_revertsWhenRecipientIsZero() public {
        config.fundsRecipient = address(0);

        vm.expectRevert(IAstreaGenesisAuctionFactory.AstreaGenesisAuctionFactory__FundsRecipientIsZero.selector);
        factory.create(address(token), AUCTION_TOKEN_ALLOCATION, abi.encode(config), SALT);
    }

    function test_optionalValidationHookIsRetainedAsBidGate() public {
        RevertingValidationHook hook = new RevertingValidationHook();
        config.validationHook = address(hook);

        ContinuousClearingAuction auction = _createFundedAuction();
        vm.roll(auction.startBlock());

        vm.deal(alice, 1 ether);
        vm.expectRevert(RevertingValidationHook.RevertingValidationHook__Rejected.selector);
        vm.prank(alice);
        auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, alice, FLOOR_PRICE, bytes(''));
    }

    function test_noBidFinalizationGraduatesAndSweepsAllUnsoldTokens() public {
        ContinuousClearingAuction auction = _createFundedAuction();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        assertTrue(auction.isGraduated());
        assertEq(auction.totalCleared(), 0);
        assertEq(auction.currencyRaised(), 0);

        vm.prank(tokensRecipient);
        auction.sweepUnsoldTokens();
        assertEq(token.balanceOf(tokensRecipient), AUCTION_TOKEN_ALLOCATION);

        uint256 fundsBefore = fundsRecipient.balance;
        vm.prank(fundsRecipient);
        auction.sweepCurrency();
        assertEq(fundsRecipient.balance, fundsBefore);
    }

    function test_undersubscribedAuctionSettlesAndSweepsGrossEthWithoutFee() public {
        ContinuousClearingAuction auction = _createFundedAuction();

        uint128 bidAmount = 1 ether;
        vm.deal(alice, bidAmount);
        vm.roll(auction.startBlock());
        vm.prank(alice);
        uint256 bidId =
            auction.submitBid{value: bidAmount}(FLOOR_PRICE + TICK_SPACING, bidAmount, alice, FLOOR_PRICE, bytes(''));

        vm.roll(auction.endBlock());
        auction.checkpoint();
        assertTrue(auction.isGraduated());

        address notRecipient = makeAddr('notRecipient');
        vm.expectRevert(
            abi.encodeWithSelector(IContinuousClearingAuction.NotAuthorized.selector, fundsRecipient, notRecipient)
        );
        vm.prank(notRecipient);
        auction.sweepCurrency();

        vm.expectRevert(
            abi.encodeWithSelector(IContinuousClearingAuction.NotAuthorized.selector, tokensRecipient, notRecipient)
        );
        vm.prank(notRecipient);
        auction.sweepUnsoldTokens();

        vm.prank(alice);
        auction.exitBid(bidId);

        vm.prank(alice);
        auction.claimTokens(bidId);
        assertGt(token.balanceOf(alice), 0);

        uint256 currencyRaised = auction.currencyRaised();
        uint256 fundsBefore = fundsRecipient.balance;
        vm.prank(fundsRecipient);
        auction.sweepCurrency();
        assertEq(fundsRecipient.balance - fundsBefore, currencyRaised);
    }

    function test_oversubscribedAuctionPartiallyFillsAndRefundsExcessEth() public {
        ContinuousClearingAuction auction = _createFundedAuction();

        uint256 bidPrice = FLOOR_PRICE + TICK_SPACING;
        uint128 bidAmount = _inputAmountForTokens(2000e18, bidPrice);
        vm.deal(alice, bidAmount);

        vm.roll(auction.startBlock());
        vm.prank(alice);
        uint256 bidId = auction.submitBid{value: bidAmount}(bidPrice, bidAmount, alice, FLOOR_PRICE, bytes(''));

        vm.roll(auction.startBlock() + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        auction.exitPartiallyFilledBid(bidId, auction.startBlock(), 0);
        assertGt(alice.balance, aliceBalanceBefore);

        vm.prank(alice);
        auction.claimTokens(bidId);
        assertApproxEqAbs(token.balanceOf(alice), AUCTION_TOKEN_ALLOCATION, 1e7);
    }

    function _createAuction() internal returns (ContinuousClearingAuction auction) {
        IDistributor distributor = factory.create(address(token), AUCTION_TOKEN_ALLOCATION, abi.encode(config), SALT);
        auction = ContinuousClearingAuction(payable(address(distributor)));
    }

    function _createFundedAuction() internal returns (ContinuousClearingAuction auction) {
        auction = _createAuction();
        token.transfer(address(auction), AUCTION_TOKEN_ALLOCATION);
        auction.onTokensReceived();
    }

    function _inputAmountForTokens(uint128 tokens, uint256 price) internal pure returns (uint128) {
        return uint128((uint256(tokens) * price) >> FixedPoint96.RESOLUTION);
    }
}
