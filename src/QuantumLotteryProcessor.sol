// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryProcessor {
    using SafeTransferLib for address;

    /**
     * @notice Process a chunk of a draw: combines winner finding and post-winner updates
     * @dev This was extracted from the main contract to reduce stack/local pressure during codegen
     * @param draws Storage mapping of all draws
     * @param players Storage mapping of all players
     * @param _hourId The hour identifier of the draw to process
     * @param _iterations Maximum number of participants to process in this call
     * @return done True if processing completed and payouts were made
     * @return cappedPlayers Array of players whose Q-scores were capped (for event emission)
     */
    function processDrawChunk(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(address => QuantumLotteryTypes.Player) storage players,
        mapping(uint256 => mapping(address => uint256)) storage, /* s_participantIndexByHour */
        IERC20 i_usdcToken,
        address i_treasury,
        uint256 _hourId,
        uint256 _iterations
    ) internal returns (bool done, address[] memory cappedPlayers) {
        QuantumLotteryTypes.Draw storage draw = draws[_hourId];
        require(draw.status == QuantumLotteryTypes.DrawStatus.RESOLVING, "Draw not ready");

        // Track players whose Q-scores hit the cap for event emission
        address[] memory cappedPlayersTemp = new address[](1000); // Max size for temp storage
        uint256 cappedCount = 0;

        // Phase A: find winner if not already picked
        if (!draw.winnerPicked) {
            uint256 participantCount = draw.participants.length;
            uint256 i = draw.processingIndex;
            uint256 end = i + _iterations;
            if (end >= participantCount) end = participantCount;

            for (; i < end; ++i) {
                draw.cumulativeScore += draw.participants[i].qScoreOnEntry;
                if (draw.randomValue < draw.cumulativeScore) {
                    draw.winner = draw.participants[i].playerAddress;
                    draw.winnerPicked = true;
                    draw.winnerIndex = i;
                    draw.processingWrapped = true;
                    draw.processingIndex = i + 1;
                    break;
                }
            }

            if (!draw.winnerPicked) {
                draw.processingIndex = i;
                // Return empty array for capped players since no processing happened
                address[] memory emptyCapped = new address[](0);
                return (false, emptyCapped);
            }
        }

        // Phase B: process updates
        uint256 effectiveBonus = draw.cosmicActive ? 3 : 1; // 3 = COSMIC_SURGE_MULTIPLIER
        uint256 participantCountB = draw.participants.length;
        uint256 j = draw.processingIndex;
        uint256 endB = j + _iterations;
        if (endB >= participantCountB) endB = participantCountB;

        for (; j < endB; ++j) {
            QuantumLotteryTypes.Participant storage part = draw.participants[j];
            if (part.playerAddress == draw.winner) {
                QuantumLotteryTypes.Player storage player = players[part.playerAddress];
                player.lastPlayedHour = uint64(_hourId);
                player.qScore = 100; // BASELINE_QSCORE
                player.streakCount = 0;
            } else {
                QuantumLotteryTypes.Player storage player = players[part.playerAddress];
                player.lastPlayedHour = uint64(_hourId);
                ++player.streakCount;
                uint256 qScoreIncrease;
                if (part.ticketTypeOnEntry == QuantumLotteryTypes.TicketType.Quantum) {
                    qScoreIncrease = 40 * effectiveBonus; // QUANTUM_TICKET_BONUS
                } else {
                    uint32 streak = player.streakCount;
                    if (streak >= 11) {
                        // BLAZING_STREAK_THRESHOLD
                        qScoreIncrease = 20 * effectiveBonus; // BLAZING_STREAK_BONUS
                    } else if (streak >= 6) {
                        // STREAK_MODE_THRESHOLD
                        qScoreIncrease = 15 * effectiveBonus; // STREAK_BONUS
                    } else {
                        qScoreIncrease = 10 * effectiveBonus; // BASE_LOSS_BONUS
                    }
                }
                player.qScore = FixedPointMathLib.min(
                    player.qScore + qScoreIncrease,
                    100000 // MAX_QSCORE
                ); // MAX_QSCORE

                // Track if player hit the cap for event emission
                if (player.qScore == 100000 && cappedCount < cappedPlayersTemp.length) {
                    // MAX_QSCORE
                    cappedPlayersTemp[cappedCount] = part.playerAddress;
                    ++cappedCount;
                }
            }
        }

        draw.processingIndex = j;

        if (draw.processingIndex >= participantCountB) {
            if (draw.processingWrapped) {
                draw.processingWrapped = false;
                draw.processingIndex = 0;
                // Return empty array for capped players since we're not done yet
                address[] memory emptyCapped = new address[](0);
                return (false, emptyCapped);
            }
            // finalize: payouts
            if (draw.prizePot != 0 && draw.winner != address(0)) {
                uint256 winnerAmount = (draw.prizePot * 92) / 100; // WINNER_PAYOUT_PERCENT / PERCENTAGE_TOTAL
                uint256 feeAmount = draw.prizePot - winnerAmount;
                address(address(i_usdcToken)).safeTransfer(draw.winner, winnerAmount);
                address(address(i_usdcToken)).safeTransfer(i_treasury, feeAmount);
                // Cannot emit WinnerPicked here - libraries can't emit contract-specific events reliably
            }

            draw.cleanupPending = true;
            draw.status = QuantumLotteryTypes.DrawStatus.RESOLVED;
            draw.cleanupIndex = 0;

            // Create properly sized array for capped players
            cappedPlayers = new address[](cappedCount);
            for (uint256 k = 0; k < cappedCount; ++k) {
                cappedPlayers[k] = cappedPlayersTemp[k];
            }
            return (true, cappedPlayers);
        }

        // Create properly sized array for capped players
        cappedPlayers = new address[](cappedCount);
        for (uint256 k = 0; k < cappedCount; ++k) {
            cappedPlayers[k] = cappedPlayersTemp[k];
        }
        return (false, cappedPlayers);
    }
}
