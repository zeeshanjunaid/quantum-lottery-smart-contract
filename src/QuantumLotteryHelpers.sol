// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryHelpers {
    /// @dev Compute the Q-score increase for a loser based on ticket type, streak and multiplier.
    function computeQScoreIncrease(
        QuantumLotteryTypes.TicketType _ticketType,
        uint32 _streakCount,
        uint256 _bonusMultiplier
    ) external pure returns (uint256) {
        // Note: keep logic identical to original implementation in base.
        if (_ticketType == QuantumLotteryTypes.TicketType.Quantum) {
            return 40 * _bonusMultiplier; // QUANTUM_TICKET_BONUS
        }
    if (_streakCount >= 11) {
            // BLAZING_STREAK_THRESHOLD
            return 20 * _bonusMultiplier; // BLAZING_STREAK_BONUS
        }
    if (_streakCount >= 6) {
            // STREAK_MODE_THRESHOLD
            return 15 * _bonusMultiplier; // STREAK_BONUS
        }
        return 10 * _bonusMultiplier; // BASE_LOSS_BONUS
    }
}
