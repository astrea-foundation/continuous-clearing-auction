// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {Bid} from 'continuous-clearing-auction/libraries/BidLib.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';

/// @notice Everything an offchain consumer needs to render and act on a single bid.
/// @dev All fields are static types so the abi-encoded struct has a fixed length
///      (`OUTCOME_LENGTH`), which `parseRevertReason` uses to tell an encoded
///      outcome apart from a bubbled-up revert.
struct PlaygroundBidOutcome {
    bool exists; // bid id is valid
    bool exited; // bid has already been exited on-chain
    bool exitableNow; // an exit transaction would succeed right now
    bool usePartialExit; // the exit must go through exitPartiallyFilledBid (with the hints below)
    bool claimableNow; // claimTokens would succeed right now (bid must be / have been exited)
    uint256 tokensFilled; // tokens the bid ends up with (simulated exit, or pending claim if already exited)
    uint256 currencyRefunded; // currency a simulated exit would refund (0 if already exited — already paid out)
    uint64 lastFullHint; // exitPartiallyFilledBid _lastFullyFilledCheckpointBlock hint
    uint64 outbidHint; // exitPartiallyFilledBid _outbidBlock hint (0 = not outbid / exit at end)
    bool needsCheckpoint; // outbidHint points at this simulation's transient checkpoint — persist a
    // checkpoint() first, then re-query for hints that survive into the exit transaction
}

/// @title PlaygroundBidLens
/// @notice DEV-ONLY lens for the local cca-playground: previews the exact exit/claim
///         outcome of a bid by simulating the calls and reverting with the result,
///         mirroring the `AuctionStateLens.state()` pattern. Call `outcome()` via
///         `eth_call`; state changes made during the simulation are always unwound.
/// @dev Not part of the production Genesis Auction surface — never deploy to mainnet.
contract PlaygroundBidLens {
    uint256 internal constant OUTCOME_LENGTH = 320; // 10 static fields * 32 bytes

    /// @notice Error thrown when the revert reason cannot be an encoded outcome
    error InvalidRevertReasonLength();

    /// @notice Preview the exit/claim outcome of `bidId` as of the current block.
    /// @dev Must be called via eth_call/staticCall — the internal simulation mutates
    ///      auction state and unwinds it by reverting.
    function outcome(IContinuousClearingAuction auction, uint256 bidId) public returns (PlaygroundBidOutcome memory) {
        try this.revertWithOutcome(auction, bidId) {}
        catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }

    /// @notice Batched `outcome()` for a set of bid ids.
    function outcomes(IContinuousClearingAuction auction, uint256[] calldata bidIds)
        external
        returns (PlaygroundBidOutcome[] memory results)
    {
        results = new PlaygroundBidOutcome[](bidIds.length);
        for (uint256 i = 0; i < bidIds.length; i++) {
            results[i] = outcome(auction, bidIds[i]);
        }
    }

    /// @notice Simulates the bid's exit (and claim, when open) and reverts with the encoded outcome.
    function revertWithOutcome(IContinuousClearingAuction auction, uint256 bidId) external {
        PlaygroundBidOutcome memory o = _simulate(auction, bidId);
        bytes memory dump = abi.encode(o);
        assembly {
            revert(add(dump, 32), mload(dump))
        }
    }

    function _simulate(IContinuousClearingAuction auction, uint256 bidId)
        internal
        returns (PlaygroundBidOutcome memory o)
    {
        if (bidId >= auction.nextBidId()) return o;
        o.exists = true;

        Bid memory bid = auction.bids(bidId);
        bool claimsOpen = block.number >= auction.claimBlock() && auction.isGraduated();

        if (bid.exitedBlock != 0) {
            // Already exited on-chain: the refund was paid at exit time; tokens (if any) wait for claim.
            o.exited = true;
            o.tokensFilled = bid.tokensFilled;
            o.claimableNow = claimsOpen && bid.tokensFilled > 0;
            return o;
        }

        // Bring the checkpoint linked list up to the current block so hint walking sees fresh state.
        // Reverts before startBlock / without tokens — no exit is possible then anyway.
        uint64 lastPersistedCheckpoint = auction.lastCheckpointedBlock();
        try auction.checkpoint() {} catch {}

        (o.lastFullHint, o.outbidHint) = _findExitHints(auction, bid);
        // An outbid hint beyond the last persisted checkpoint only exists inside this
        // simulation — the caller must persist a checkpoint before the hint is usable.
        o.needsCheckpoint = o.outbidHint != 0 && o.outbidHint > lastPersistedCheckpoint;

        address owner = bid.owner;
        uint256 balanceBefore = owner.balance;

        // Prefer the simple exit; fall back to the hinted partial exit.
        try auction.exitBid(bidId) {
            o.exitableNow = true;
        } catch {
            try auction.exitPartiallyFilledBid(bidId, o.lastFullHint, o.outbidHint) {
                o.exitableNow = true;
                o.usePartialExit = true;
            } catch {}
        }

        if (o.exitableNow) {
            // ETH-only playground: the refund arrives as native currency.
            o.currencyRefunded = owner.balance - balanceBefore;
            o.tokensFilled = auction.bids(bidId).tokensFilled;
            if (claimsOpen && o.tokensFilled > 0) {
                try auction.claimTokens(bidId) {
                    o.claimableNow = true;
                } catch {}
            }
        }
    }

    /// @notice Walk the checkpoint linked list from the bid's start block to find the
    ///         `exitPartiallyFilledBid` hints.
    /// @return lastFull last checkpointed block whose clearing price is below the bid's max
    ///         while the following checkpoint is at/above it (0 if never crossed)
    /// @return outbid first checkpointed block whose clearing price is strictly above the
    ///         bid's max (0 if the price never exceeded the max)
    function _findExitHints(IContinuousClearingAuction auction, Bid memory bid)
        internal
        view
        returns (uint64 lastFull, uint64 outbid)
    {
        uint64 blockCursor = bid.startBlock;
        Checkpoint memory cp = auction.checkpoints(blockCursor);
        // A checkpoint always exists at the bid's start block; walk forward from there.
        while (true) {
            uint64 nextBlock = cp.next;
            if (cp.clearingPrice > bid.maxPrice) {
                outbid = blockCursor;
                break;
            }
            if (nextBlock == 0) break; // reached the latest checkpoint without crossing
            Checkpoint memory nextCp = auction.checkpoints(nextBlock);
            if (cp.clearingPrice < bid.maxPrice && nextCp.clearingPrice >= bid.maxPrice) {
                lastFull = blockCursor;
            }
            blockCursor = nextBlock;
            cp = nextCp;
        }
    }

    /// @notice Decode an encoded outcome from the revert reason, bubbling anything else up.
    function parseRevertReason(bytes memory reason) internal pure returns (PlaygroundBidOutcome memory) {
        if (reason.length != OUTCOME_LENGTH) {
            if (reason.length > 0) {
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
            } else {
                revert InvalidRevertReasonLength();
            }
        }
        return abi.decode(reason, (PlaygroundBidOutcome));
    }
}
