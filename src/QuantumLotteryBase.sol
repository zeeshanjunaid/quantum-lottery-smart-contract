// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {VRFConsumerBaseV2Plus} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from
    "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";
import {QuantumLotteryHelpers} from "./QuantumLotteryHelpers.sol";
import {QuantumLotteryProcessor} from "./QuantumLotteryProcessor.sol";
import {QuantumLotteryFulfillment} from "./QuantumLotteryFulfillment.sol";
import {QuantumLotteryEntry} from "./QuantumLotteryEntry.sol";
import {QuantumLotteryCleanup} from "./QuantumLotteryCleanup.sol";
import {QuantumLotteryRefunds} from "./QuantumLotteryRefunds.sol";
import {QuantumLotteryWithdraw} from "./QuantumLotteryWithdraw.sol";
import {QuantumLotteryForceResolve} from "./QuantumLotteryForceResolve.sol";

/**
 * @title QuantumLotteryBase
 * @notice Base implementation extracted to reduce per-contract codegen complexity for coverage.
 */
contract QuantumLotteryBase is VRFConsumerBaseV2Plus, ReentrancyGuard, QuantumLotteryTypes {
    /// @dev This contract is USDC-only. Reject any ETH transfers explicitly.
    /// No receive() defined; ETH sends will hit nonpayable fallback and revert.
    fallback() external {
        revert("ETH not accepted");
    }
    // =============================================================
    //                        CORE USER FUNCTIONS
    // =============================================================
    /// @notice Buy a ticket for the current hour’s draw.
    /// @param ticketType Ticket type: Standard or Quantum

    function buyTicket(QuantumLotteryTypes.TicketType ticketType) external nonReentrant {
        // Validate enum input to avoid invalid values being treated as Quantum by default
        if (uint256(ticketType) > uint256(QuantumLotteryTypes.TicketType.Quantum)) {
            revert("Invalid ticket type");
        }
        uint256 currentHourId = block.timestamp / SECONDS_PER_HOUR;
        Draw storage draw = draws[currentHourId];
        if (draw.status != DrawStatus.OPEN) revert DrawNotOpen();
        // NOTE: Slither "dangerous strict equality" informational warning
        // is expected here. We intentionally compare the lastEnteredHourPlusOne
        // sentinel against currentHourId + 1 to prevent duplicate entries in the
        // same hour while allowing a user to participate in consecutive hours.
        if (lastEnteredHourPlusOne[msg.sender] == currentHourId + 1) {
            revert PlayerAlreadyEntered();
        }
        if (draw.participants.length >= MAX_PARTICIPANTS) revert DrawIsFull();

        Player storage player = players[msg.sender];
        bool isFirstTimePlayer = player.lastPlayedHour == 0;
        bool isStreakBroken = currentHourId > (player.lastPlayedHour + 1);
        uint256 ticketPrice = ticketType == TicketType.Standard ? STANDARD_TICKET_PRICE : QUANTUM_TICKET_PRICE;

        if (isFirstTimePlayer) {
            player.qScore = BASELINE_QSCORE;
        }
        if (isStreakBroken) {
            player.streakCount = 0;
        }
        _recordTicketPurchase(currentHourId, msg.sender, player.qScore, ticketType, ticketPrice);
    }

    constructor(
        address usdcAddress,
        address treasuryAddress,
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 gasLane
    ) payable VRFConsumerBaseV2Plus(vrfCoordinator) {
        require(usdcAddress != address(0), "USDC address cannot be zero");
        require(treasuryAddress != address(0), "Treasury address cannot be zero");
        require(vrfCoordinator != address(0), "VRF Coordinator cannot be zero");
        i_usdcToken = IERC20(usdcAddress);
        i_treasury = treasuryAddress;
        i_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
    }

    // State variables
    mapping(address => QuantumLotteryTypes.Player) public players;
    mapping(uint256 => QuantumLotteryTypes.Draw) public draws;
    mapping(uint256 => uint256) public s_requestIdToHourIdPlusOne;
    mapping(address => uint256) public lastEnteredHourPlusOne;
    mapping(uint256 => mapping(address => uint256)) private s_participantIndexByHour;
    mapping(uint256 => mapping(address => bool)) private s_refundClaimedByHour;
    uint256 public nextCosmicSurgeHour = type(uint256).max;

    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    IVRFCoordinatorV2Plus private immutable i_vrfCoordinator;
    IERC20 public immutable i_usdcToken;
    address public immutable i_treasury;

    using SafeTransferLib for address;

    /// @dev Internal helper to record participant, update indices and accounting, and emit event.
    function _recordTicketPurchase(
        uint256 hourId,
        address playerAddr,
        uint256 qScoreOnEntry,
        QuantumLotteryTypes.TicketType ticketType,
        uint256 ticketPrice
    ) internal {
        // Delegate storage updates to entry library to reduce contract locals
        QuantumLotteryEntry.recordTicketPurchase(
            draws,
            lastEnteredHourPlusOne,
            s_participantIndexByHour,
            hourId,
            playerAddr,
            qScoreOnEntry,
            ticketType,
            ticketPrice
        );
        emit TicketPurchased(hourId, playerAddr, ticketType, qScoreOnEntry);
        // Solady SafeTransferLib
        address(address(i_usdcToken)).safeTransferFrom(playerAddr, address(this), ticketPrice);
    }

    // =============================================================
    //                        VRF & ADMIN FUNCTIONS
    // =============================================================
    /// @notice Request randomness to pick a winner for a past hour’s draw.
    /// @param hourId The hour to close (must be in the past and have participants)
    function requestRandomWinner(uint256 hourId) external onlyOwner nonReentrant returns (uint256 requestId) {
        if (hourId >= block.timestamp / SECONDS_PER_HOUR) {
            revert DrawCannotBeClosedYet();
        }
        Draw storage drawToClose = draws[hourId];
        if (drawToClose.participants.length == 0) {
            revert DrawHasNoParticipants();
        }
        if (drawToClose.status != DrawStatus.OPEN) {
            revert DrawAlreadyResolvedOrCalculating();
        }

        drawToClose.status = DrawStatus.CALCULATING_WINNER;
        drawToClose.requestTimestamp = block.timestamp;

        // Note: if Chainlink VRF repeatedly fails to service requests, a draw
        // may remain in CALCULATING_WINNER state until the owner force-resolves it.
        // This is expected behavior to avoid unsafe automatic fallback logic.

        requestId = _sendVrfRequest(hourId);
    }

    /// @dev Sends the randomness request to the trusted Chainlink VRF coordinator.
    ///
    /// Rationale & Slither notes:
    /// - This function performs an external call before updating some state (the
    ///   requestId mapping) because we need the returned requestId from the coordinator.
    /// - The caller (requestRandomWinner) has already set the draw status to
    ///   CALCULATING_WINNER and recorded the request timestamp before invoking this.
    /// - Chainlink VRF cannot synchronously callback within the same transaction,
    ///   so typical reentrancy is not possible here. On failure, we revert the
    ///   status to OPEN inside the catch block to keep state consistent.
    /// - This pattern is CEI-safe given the trust model and the VRF call semantics.
    function _sendVrfRequest(uint256 hourId) internal returns (uint256 requestId) {
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_gasLane,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: CALLBACK_GAS_LIMIT,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        try i_vrfCoordinator.requestRandomWords(req) returns (uint256 _requestId) {
            requestId = _requestId;
            s_requestIdToHourIdPlusOne[requestId] = hourId + 1;
            emit WinnerSelectionRequested(hourId, requestId);
        } catch {
            revert VrfRequestFailed();
        }
    }

    /// @dev VRF callback entrypoint; records randomness and prepares the draw for processing.
    /// @param requestId The VRF request id
    /// @param randomWords The random words returned by VRF
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override nonReentrant {
        uint256 hourId = _validateAndClearRequest(requestId);
        Draw storage draw = draws[hourId];
        if (draw.status != DrawStatus.CALCULATING_WINNER) {
            revert InvalidRequestIdForLottery();
        }

        // Record totals and random value, then allow chunked processing to finish work
        uint256 totalQScoreInPool = QuantumLotteryFulfillment.computeTotalQScore(draws, hourId);
        require(totalQScoreInPool != 0, "Total Q-Score pool is zero");

        uint256 rv = randomWords[0] % totalQScoreInPool;
        // finalizeFulfill moved into library to reduce local stack pressure;
        // it returns the possibly-updated nextCosmicSurgeHour which we persist.
        nextCosmicSurgeHour =
            QuantumLotteryFulfillment.finalizeFulfill(draws, hourId, rv, totalQScoreInPool, nextCosmicSurgeHour);
        emit RandomnessFulfilled(hourId, requestId, totalQScoreInPool);
    }

    /// @dev Validate incoming requestId mapping and clear it. Returns hourId.
    function _validateAndClearRequest(uint256 requestId) internal returns (uint256) {
        uint256 hourIdPlusOne = s_requestIdToHourIdPlusOne[requestId];
        if (hourIdPlusOne == 0) revert InvalidRequestIdForLottery();
        delete s_requestIdToHourIdPlusOne[requestId];
        return hourIdPlusOne - 1;
    }

    /// @dev Finalize fulfillment state for a draw after randomness is provided.
    // finalizeFulfill logic delegated to QuantumLotteryFulfillment

    /// @dev Helper to compute total Q-score of participants for a draw.
    // total Q-score computation delegated to QuantumLotteryFulfillment.computeTotalQScore

    /// @dev Splits winner-selection and post-winner updates across multiple transactions
    /// to avoid high callback gas usage when many participants are present.
    /// @notice Process a chunk of a resolved draw; call repeatedly until it returns true.
    /// @param hourId The hour identifier of the draw to process
    /// @param iterations Maximum number of participants to process in this call
    /// @return done True if processing completed and payouts were made
    function processDrawChunk(uint256 hourId, uint256 iterations) external nonReentrant returns (bool done) {
        require(iterations != 0, "Zero iterations");
        // Delegate heavy processing to the library to reduce contract-local
        // stack pressure during compilation (helps coverage runs).
        (bool finished, address[] memory cappedPlayers) = QuantumLotteryProcessor.processDrawChunk(
            draws, players, s_participantIndexByHour, i_usdcToken, i_treasury, hourId, iterations
        );

        // Emit QScoreCapped events for players who hit the maximum
        for (uint256 i = 0; i < cappedPlayers.length; ++i) {
            emit QScoreCapped(cappedPlayers[i], hourId, MAX_QSCORE);
        }

        // If the library finalized the draw (performed payouts), emit the
        // WinnerPicked event here so external observers/tests see the same
        // behavior as the original in-contract finalizer.
        if (finished) {
            Draw storage draw = draws[hourId];
            uint256 prizePot = draw.prizePot;
            uint256 winnerAmount = (prizePot * WINNER_PAYOUT_PERCENT) / PERCENTAGE_TOTAL;
            uint256 feeAmount = prizePot - winnerAmount;
            emit WinnerPicked(hourId, draw.winner, winnerAmount, feeAmount, draw.totalQScoreInPool);
            return true;
        }

        return false;
    }

    /// @notice Remove participant-related mapping entries in chunks to free storage
    /// @notice Cleanup participant-related mappings in chunks after resolution.
    /// @param hourId The hour identifier to cleanup
    /// @param iterations Maximum deletions to perform this call
    function cleanupDrawChunk(uint256 hourId, uint256 iterations) external returns (bool done) {
        require(iterations != 0, "Zero iterations");
        Draw storage draw = draws[hourId];
        require(draw.cleanupPending, "No cleanup pending");
        return QuantumLotteryCleanup.cleanupDrawChunkStorage(
            draws, s_participantIndexByHour, s_refundClaimedByHour, hourId, iterations
        );
    }

    /// @notice Returns the remaining reserved refunds liability for a given draw
    /// @notice View reserved refunds liability for a draw.
    /// @param hourId The hour identifier
    function getReservedRefunds(uint256 hourId) external view returns (uint256) {
        return draws[hourId].reservedRefunds;
    }

    // _finalizeDraw logic delegated to QuantumLotteryProcessor (payouts and finalization).

    // Winner/loser per-index update logic delegated to QuantumLotteryProcessor.

    /// @dev Compute the Q-score increase for a loser based on ticket type, streak and multiplier.
    // ...logic moved to QuantumLotteryHelpers to reduce in-contract inlining and
    // limit stack usage during codegen for coverage runs.

    /// @notice Schedule a cosmic surge for a future timestamp (rounded to hour).
    /// @param timestamp The future timestamp for the surge
    function setNextCosmicSurge(uint256 timestamp) external onlyOwner {
        uint256 hourId = timestamp / SECONDS_PER_HOUR;
        // Require scheduling for the current or a future hour (not a past hour)
        if (hourId < block.timestamp / SECONDS_PER_HOUR) {
            revert("Hour in past");
        }
        // prevent accidental double-scheduling; require explicit reset if needed
        require(nextCosmicSurgeHour == type(uint256).max, "Cosmic surge already scheduled");
        nextCosmicSurgeHour = hourId;
        emit CosmicSurgeScheduled(hourId);
    }

    /// @notice Force resolve a stuck draw after the VRF timeout.
    /// @param hourId The hour identifier to force resolve
    function forceResolveDraw(uint256 hourId) external onlyOwner nonReentrant {
        Draw storage draw = draws[hourId];
        if (draw.status != DrawStatus.CALCULATING_WINNER) revert DrawNotStuck();
        if (block.timestamp < draw.requestTimestamp + DRAW_RESOLUTION_TIMEOUT) {
            revert TimeoutNotReached();
        }
        uint256 _pc = QuantumLotteryForceResolve.forceResolveCore(draws, hourId);
        emit DrawForceResolved(hourId);
        emit DrawForceResolvedWithCount(hourId, _pc);
    }

    /// @notice Claim your refund from a force-resolved draw.
    /// @param hourId The hour identifier
    function claimRefund(uint256 hourId) external nonReentrant {
        if (!draws[hourId].forceResolved) revert DrawNotStuck();
        uint256 refundAmount = QuantumLotteryRefunds.claimRefundCore(
            draws,
            s_participantIndexByHour,
            s_refundClaimedByHour,
            hourId,
            msg.sender,
            STANDARD_TICKET_PRICE,
            QUANTUM_TICKET_PRICE
        );
        _executeRefundTransfer(hourId, msg.sender, refundAmount);
    }

    /// @notice Withdraw unclaimed refunds after the grace period.
    /// @param hourId The hour identifier
    /// @param to Recipient address
    function withdrawUnclaimed(uint256 hourId, address to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        Draw storage draw = draws[hourId];
        require(draw.forceResolved, "Draw not force-resolved");
        if (block.timestamp < draw.requestTimestamp + UNCLAIMED_REFUND_PERIOD) {
            revert("Too early to withdraw");
        }
        uint256 bal = i_usdcToken.balanceOf(address(this));
        uint256 toWithdraw = QuantumLotteryWithdraw.computeWithdrawUnclaimed(draws, hourId, bal);
        _executeWithdrawUnclaimed(hourId, to, toWithdraw);
    }

    function _executeRefundTransfer(uint256 hourId, address to, uint256 amount) internal {
        address(address(i_usdcToken)).safeTransfer(to, amount);
        emit RefundIssued(hourId, to, amount, draws[hourId].reservedRefunds);
    }

    function _executeWithdrawUnclaimed(uint256 hourId, address to, uint256 amount) internal {
        address(address(i_usdcToken)).safeTransfer(to, amount);
        emit WithdrawUnclaimed(hourId, to, amount, draws[hourId].reservedRefunds);
    }

    function cancelNextCosmicSurge() external onlyOwner {
        require(nextCosmicSurgeHour != type(uint256).max, "No surge scheduled");
        uint256 canceled = nextCosmicSurgeHour;
        nextCosmicSurgeHour = type(uint256).max;
        emit CosmicSurgeCanceled(canceled);
    }

    /// @notice View the prize pot for a given hour.
    /// @param hourId The hour identifier
    function getPrizePot(uint256 hourId) external view returns (uint256) {
        return draws[hourId].prizePot;
    }

    /// @notice View the winner address for a given hour.
    /// @param hourId The hour identifier
    function getWinner(uint256 hourId) external view returns (address) {
        return draws[hourId].winner;
    }

    /// @notice Emergency withdraw arbitrary ERC20 tokens by the owner.
    /// @param token ERC20 token address
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token address");
        address(token).safeTransfer(owner(), amount);
        emit EmergencyWithdraw(token, owner(), amount);
    }

    /// @notice Testing helper: zero out a participant slot.
    function debugZeroParticipant(uint256 hourId, uint256 index) external onlyOwner {
        Draw storage draw = draws[hourId];
        if (index >= draw.participants.length) revert IndexOutOfBounds();
        draw.participants[index].playerAddress = address(0);
    }

    /// @notice Testing helper: set a player's recorded state.
    function debugSetPlayer(address player, uint64 lastPlayedHour, uint32 streakCount, uint256 qScore)
        external
        onlyOwner
    {
        Player storage p = players[player];
        p.lastPlayedHour = lastPlayedHour;
        p.streakCount = streakCount;
        p.qScore = qScore;
    }

    /// @notice View the last hour a player entered (0 if never).
    function lastEnteredHour(address player) public view returns (uint256) {
        uint256 v = lastEnteredHourPlusOne[player];
        if (v == 0) return 0;
        return v - 1;
    }

    /// @notice View the draw status for an hour.
    function getDrawStatus(uint256 hourId) public view returns (DrawStatus) {
        return draws[hourId].status;
    }

    /// @notice View a participant by index for a given hour.
    function getParticipant(uint256 hourId, uint256 index) public view returns (Participant memory) {
        if (index >= draws[hourId].participants.length) {
            revert IndexOutOfBounds();
        }
        return draws[hourId].participants[index];
    }

    /// @notice View the number of participants for a given hour.
    function getParticipantsCount(uint256 hourId) public view returns (uint256) {
        return draws[hourId].participants.length;
    }
}
