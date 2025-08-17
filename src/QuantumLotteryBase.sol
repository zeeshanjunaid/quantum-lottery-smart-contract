// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
contract QuantumLotteryBase is
    Ownable,
    VRFConsumerBaseV2,
    ReentrancyGuard,
    QuantumLotteryTypes
{
    // =============================================================
    //                        CORE USER FUNCTIONS
    // =============================================================
    function buyTicket(
        QuantumLotteryTypes.TicketType _ticketType
    ) external nonReentrant {
        uint256 currentHourId = block.timestamp / SECONDS_PER_HOUR;
        Draw storage draw = draws[currentHourId];
        if (draw.status != DrawStatus.OPEN) revert DrawNotOpen();
        if (lastEnteredHourPlusOne[msg.sender] == currentHourId + 1) {
            revert PlayerAlreadyEntered();
        }
        if (draw.participants.length >= MAX_PARTICIPANTS) revert DrawIsFull();

        Player storage player = players[msg.sender];
        bool isFirstTimePlayer = player.lastPlayedHour == 0;
        bool isStreakBroken = currentHourId > (player.lastPlayedHour + 1);
        uint256 ticketPrice = _ticketType == TicketType.Standard
            ? STANDARD_TICKET_PRICE
            : QUANTUM_TICKET_PRICE;

        if (isFirstTimePlayer) {
            player.qScore = BASELINE_QSCORE;
        }
        if (isStreakBroken) {
            player.streakCount = 0;
        }
        _recordTicketPurchase(
            currentHourId,
            msg.sender,
            player.qScore,
            _ticketType,
            ticketPrice
        );
    }

    constructor(
        address _usdcAddress,
        address _treasuryAddress,
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _gasLane
    ) Ownable(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        require(_usdcAddress != address(0), "USDC address cannot be zero");
        require(
            _treasuryAddress != address(0),
            "Treasury address cannot be zero"
        );
        require(
            _vrfCoordinator != address(0),
            "VRF Coordinator cannot be zero"
        );
        i_usdcToken = IERC20(_usdcAddress);
        i_treasury = _treasuryAddress;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_subscriptionId = _subscriptionId;
        i_gasLane = _gasLane;
    }

    // State variables
    mapping(address => QuantumLotteryTypes.Player) public players;
    mapping(uint256 => QuantumLotteryTypes.Draw) public draws;
    mapping(uint256 => uint256) public s_requestIdToHourIdPlusOne;
    mapping(address => uint256) public lastEnteredHourPlusOne;
    mapping(uint256 => mapping(address => uint256))
        private s_participantIndexByHour;
    mapping(uint256 => mapping(address => bool)) private s_refundClaimedByHour;
    uint256 public nextCosmicSurgeHour = type(uint256).max;

    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    IERC20 public immutable i_usdcToken;
    address public immutable i_treasury;
    using SafeERC20 for IERC20;

    /// @dev Internal helper to record participant, update indices and accounting, and emit event.
    function _recordTicketPurchase(
        uint256 _hourId,
        address _player,
        uint256 _qScoreOnEntry,
        QuantumLotteryTypes.TicketType _ticketType,
        uint256 _ticketPrice
    ) internal {
        // Delegate storage updates to entry library to reduce contract locals
        QuantumLotteryEntry.recordTicketPurchase(
            draws,
            lastEnteredHourPlusOne,
            s_participantIndexByHour,
            _hourId,
            _player,
            _qScoreOnEntry,
            _ticketType,
            _ticketPrice
        );
        emit TicketPurchased(_hourId, _player, _ticketType, _qScoreOnEntry);
        i_usdcToken.safeTransferFrom(_player, address(this), _ticketPrice);
    }

    // =============================================================
    //                        VRF & ADMIN FUNCTIONS
    // =============================================================
    function requestRandomWinner(
        uint256 _hourId
    ) external onlyOwner nonReentrant returns (uint256 requestId) {
        if (_hourId >= block.timestamp / SECONDS_PER_HOUR)
            revert DrawCannotBeClosedYet();
        Draw storage drawToClose = draws[_hourId];
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

        requestId = _sendVrfRequest(_hourId);
    }

    function _sendVrfRequest(
        uint256 _hourId
    ) internal returns (uint256 requestId) {
        try
            i_vrfCoordinator.requestRandomWords(
                i_gasLane,
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                CALLBACK_GAS_LIMIT,
                NUM_WORDS
            )
        returns (uint256 _requestId) {
            requestId = _requestId;
            s_requestIdToHourIdPlusOne[requestId] = _hourId + 1;
            emit WinnerSelectionRequested(_hourId, requestId);
        } catch {
            draws[_hourId].status = DrawStatus.OPEN;
            revert VrfRequestFailed();
        }
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override nonReentrant {
        uint256 hourId = _validateAndClearRequest(_requestId);
        Draw storage draw = draws[hourId];
        if (draw.status != DrawStatus.CALCULATING_WINNER) {
            revert InvalidRequestIdForLottery();
        }

        // Record totals and random value, then allow chunked processing to finish work
        uint256 totalQScoreInPool = QuantumLotteryFulfillment
            .computeTotalQScore(draws, hourId);
        require(totalQScoreInPool > 0, "Total Q-Score pool is zero");

        uint256 rv = _randomWords[0] % totalQScoreInPool;
        // finalizeFulfill moved into library to reduce local stack pressure;
        // it returns the possibly-updated nextCosmicSurgeHour which we persist.
        nextCosmicSurgeHour = QuantumLotteryFulfillment.finalizeFulfill(
            draws,
            hourId,
            rv,
            totalQScoreInPool,
            nextCosmicSurgeHour
        );
        emit RandomnessFulfilled(hourId, _requestId, totalQScoreInPool);
    }

    /// @dev Validate incoming requestId mapping and clear it. Returns hourId.
    function _validateAndClearRequest(
        uint256 _requestId
    ) internal returns (uint256) {
        uint256 hourIdPlusOne = s_requestIdToHourIdPlusOne[_requestId];
        if (hourIdPlusOne == 0) revert InvalidRequestIdForLottery();
        delete s_requestIdToHourIdPlusOne[_requestId];
        return hourIdPlusOne - 1;
    }

    /// @dev Finalize fulfillment state for a draw after randomness is provided.
    // finalizeFulfill logic delegated to QuantumLotteryFulfillment

    /// @dev Helper to compute total Q-score of participants for a draw.
    // total Q-score computation delegated to QuantumLotteryFulfillment.computeTotalQScore

    /// @notice Process a chunk of a resolved draw. Call repeatedly until it returns true.
    /// @dev Splits winner-selection and post-winner updates across multiple transactions
    /// to avoid high callback gas usage when many participants are present.
    /// @param _hourId The hour identifier of the draw to process
    /// @param _iterations Maximum number of participants to process in this call
    /// @return done True if processing completed and payouts were made
    function processDrawChunk(
        uint256 _hourId,
        uint256 _iterations
    ) external nonReentrant returns (bool done) {
        // Delegate heavy processing to the library to reduce contract-local
        // stack pressure during compilation (helps coverage runs).
        (
            bool finished,
            address[] memory cappedPlayers
        ) = QuantumLotteryProcessor.processDrawChunk(
                draws,
                players,
                s_participantIndexByHour,
                i_usdcToken,
                i_treasury,
                _hourId,
                _iterations
            );

        // Emit QScoreCapped events for players who hit the maximum
        for (uint256 i = 0; i < cappedPlayers.length; i++) {
            emit QScoreCapped(cappedPlayers[i], _hourId, MAX_QSCORE);
        }

        // If the library finalized the draw (performed payouts), emit the
        // WinnerPicked event here so external observers/tests see the same
        // behavior as the original in-contract finalizer.
        if (finished) {
            Draw storage draw = draws[_hourId];
            uint256 prizePot = draw.prizePot;
            uint256 winnerAmount = (prizePot * WINNER_PAYOUT_PERCENT) /
                PERCENTAGE_TOTAL;
            uint256 feeAmount = prizePot - winnerAmount;
            emit WinnerPicked(
                _hourId,
                draw.winner,
                winnerAmount,
                feeAmount,
                draw.totalQScoreInPool
            );
            return true;
        }

        return false;
    }

    /// @notice Remove participant-related mapping entries in chunks to free storage
    /// @dev Call repeatedly until it returns true. This avoids a large gas spike when
    /// deleting per-participant mappings for big draws.
    function cleanupDrawChunk(
        uint256 _hourId,
        uint256 _iterations
    ) external returns (bool done) {
        Draw storage draw = draws[_hourId];
        require(draw.cleanupPending, "No cleanup pending");
        return
            QuantumLotteryCleanup.cleanupDrawChunkStorage(
                draws,
                s_participantIndexByHour,
                s_refundClaimedByHour,
                _hourId,
                _iterations
            );
    }

    /// @notice Returns the remaining reserved refunds liability for a given draw
    function getReservedRefunds(
        uint256 _hourId
    ) external view returns (uint256) {
        return draws[_hourId].reservedRefunds;
    }

    // internal helper: find winner scanning up to _iterations participants starting from draw.processingIndex
    function _findWinnerChunk(
        uint256 _hourId,
        uint256 _iterations
    ) internal returns (bool) {
        // Delegate to processor: processDrawChunk handles winner-finding as Phase A.
        // We call with the provided iterations and ignore finalization signal here.
        (bool finished, ) = QuantumLotteryProcessor.processDrawChunk(
            draws,
            players,
            s_participantIndexByHour,
            i_usdcToken,
            i_treasury,
            _hourId,
            _iterations
        );
        return finished;
    }

    /// @dev Check a single participant index for winner condition and update draw state.
    function _checkWinnerAtIndex(
        uint256 _hourId,
        uint256 /* _index */
    ) internal returns (bool) {
        // This helper is now covered by QuantumLotteryProcessor; keep thin wrapper
        // for any legacy callers by invoking processDrawChunk for a single iteration.
        (bool finished, ) = QuantumLotteryProcessor.processDrawChunk(
            draws,
            players,
            s_participantIndexByHour,
            i_usdcToken,
            i_treasury,
            _hourId,
            1
        );
        return finished;
    }

    // internal helper: process post-winner updates for up to _iterations participants; returns true when all done
    function _processUpdatesChunk(
        uint256 _hourId,
        uint256 _iterations,
        uint256 /* _bonusMultiplier */
    ) internal returns (bool) {
        // Delegate to processor which handles post-winner updates and finalization
        (bool finished, ) = QuantumLotteryProcessor.processDrawChunk(
            draws,
            players,
            s_participantIndexByHour,
            i_usdcToken,
            i_treasury,
            _hourId,
            _iterations
        );
        return finished;
    }

    // _finalizeDraw logic delegated to QuantumLotteryProcessor (payouts and finalization).

    /// @dev Apply post-winner updates for a participant identified by index in the draw participants array.
    function _applyPostWinnerUpdateByIndex(
        uint256 _hourId,
        uint256 /* _index */,
        uint256 /* _bonusMultiplier */,
        address /* _winner */
    ) internal {
        // Delegate logic to the processor; call it for a single iteration to process this index
        QuantumLotteryProcessor.processDrawChunk(
            draws,
            players,
            s_participantIndexByHour,
            i_usdcToken,
            i_treasury,
            _hourId,
            1
        );
    }

    // Winner/loser per-index update logic delegated to QuantumLotteryProcessor.

    /// @dev Compute the Q-score increase for a loser based on ticket type, streak and multiplier.
    // ...logic moved to QuantumLotteryHelpers to reduce in-contract inlining and
    // limit stack usage during codegen for coverage runs.

    function setNextCosmicSurge(uint256 _timestamp) external onlyOwner {
        uint256 hourId = _timestamp / SECONDS_PER_HOUR;
        // prevent accidental double-scheduling; require explicit reset if needed
        require(
            nextCosmicSurgeHour == type(uint256).max,
            "Cosmic surge already scheduled"
        );
        nextCosmicSurgeHour = hourId;
        emit CosmicSurgeScheduled(hourId);
    }

    function forceResolveDraw(uint256 _hourId) external onlyOwner nonReentrant {
        Draw storage draw = draws[_hourId];
        if (draw.status != DrawStatus.CALCULATING_WINNER) revert DrawNotStuck();
        if (block.timestamp < draw.requestTimestamp + DRAW_RESOLUTION_TIMEOUT) {
            revert TimeoutNotReached();
        }
        uint256 _pc = QuantumLotteryForceResolve.forceResolveCore(
            draws,
            _hourId
        );
        emit DrawForceResolved(_hourId);
        emit DrawForceResolvedWithCount(_hourId, _pc);
    }

    function claimRefund(uint256 _hourId) external nonReentrant {
        if (!draws[_hourId].forceResolved) revert DrawNotStuck();
        uint256 refundAmount = QuantumLotteryRefunds.claimRefundCore(
            draws,
            s_participantIndexByHour,
            s_refundClaimedByHour,
            _hourId,
            msg.sender,
            STANDARD_TICKET_PRICE,
            QUANTUM_TICKET_PRICE
        );
        _executeRefundTransfer(_hourId, msg.sender, refundAmount);
    }

    function withdrawUnclaimed(
        uint256 _hourId,
        address _to
    ) external onlyOwner {
        Draw storage draw = draws[_hourId];
        require(draw.forceResolved, "Draw not force-resolved");
        require(
            block.timestamp >= draw.requestTimestamp + UNCLAIMED_REFUND_PERIOD,
            "Too early to withdraw"
        );
        uint256 bal = i_usdcToken.balanceOf(address(this));
        uint256 toWithdraw = QuantumLotteryWithdraw.computeWithdrawUnclaimed(
            draws,
            _hourId,
            bal
        );
        _executeWithdrawUnclaimed(_hourId, _to, toWithdraw);
    }

    function _executeRefundTransfer(
        uint256 _hourId,
        address _to,
        uint256 _amount
    ) internal {
        i_usdcToken.safeTransfer(_to, _amount);
        emit RefundIssued(
            _hourId,
            _to,
            _amount,
            draws[_hourId].reservedRefunds
        );
    }

    function _executeWithdrawUnclaimed(
        uint256 _hourId,
        address _to,
        uint256 _amount
    ) internal {
        i_usdcToken.safeTransfer(_to, _amount);
        emit WithdrawUnclaimed(
            _hourId,
            _to,
            _amount,
            draws[_hourId].reservedRefunds
        );
    }

    function cancelNextCosmicSurge() external onlyOwner {
        require(nextCosmicSurgeHour != type(uint256).max, "No surge scheduled");
        uint256 canceled = nextCosmicSurgeHour;
        nextCosmicSurgeHour = type(uint256).max;
        emit CosmicSurgeCanceled(canceled);
    }

    function getPrizePot(uint256 _hourId) external view returns (uint256) {
        return draws[_hourId].prizePot;
    }

    function getWinner(uint256 _hourId) external view returns (address) {
        return draws[_hourId].winner;
    }

    function emergencyWithdraw(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        IERC20(_token).safeTransfer(owner(), _amount);
        emit EmergencyWithdraw(_token, owner(), _amount);
    }

    function debugZeroParticipant(
        uint256 _hourId,
        uint256 _index
    ) external onlyOwner {
        Draw storage draw = draws[_hourId];
        if (_index >= draw.participants.length) revert IndexOutOfBounds();
        draw.participants[_index].playerAddress = address(0);
    }

    function debugSetPlayer(
        address _player,
        uint64 _lastPlayedHour,
        uint32 _streakCount,
        uint256 _qScore
    ) external onlyOwner {
        Player storage p = players[_player];
        p.lastPlayedHour = _lastPlayedHour;
        p.streakCount = _streakCount;
        p.qScore = _qScore;
    }

    function lastEnteredHour(address _player) public view returns (uint256) {
        uint256 v = lastEnteredHourPlusOne[_player];
        if (v == 0) return 0;
        return v - 1;
    }

    function getDrawStatus(uint256 _hourId) public view returns (DrawStatus) {
        return draws[_hourId].status;
    }

    function getParticipant(
        uint256 _hourId,
        uint256 _index
    ) public view returns (Participant memory) {
        if (_index >= draws[_hourId].participants.length) {
            revert IndexOutOfBounds();
        }
        return draws[_hourId].participants[_index];
    }

    function getParticipantsCount(
        uint256 _hourId
    ) public view returns (uint256) {
        return draws[_hourId].participants.length;
    }
}
