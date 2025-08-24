// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryFulfillment {
    /// @dev Compute total Q-score for draw (moved out of contract to reduce stack pressure)
    /// @dev Gas-optimized with overflow protection
    function computeTotalQScore(mapping(uint256 => QuantumLotteryTypes.Draw) storage draws, uint256 hourId)
        internal
        view
        returns (uint256)
    {
        QuantumLotteryTypes.Draw storage d = draws[hourId];
        uint256 participantCount = d.participants.length;

        // Gas limit protection: if too many participants, this could fail
        // The VRF callback has a 2.5M gas limit, so we need to be careful
        if (participantCount > 500) revert QuantumLotteryTypes.TooManyParticipants(); // MAX_PARTICIPANTS

        uint256 total = 0;
        for (uint256 i = 0; i < participantCount; ++i) {
            uint256 qScore = d.participants[i].qScoreOnEntry;
            // Overflow protection
            if (total > type(uint256).max - qScore) revert QuantumLotteryTypes.QScoreTotalOverflow();
            total += qScore;
        }
        return total;
    }

    /// @dev Finalize fulfill: set draw fields and handle cosmic surge flag (no events emitted here)
    function finalizeFulfill(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        uint256 hourId,
        uint256 randomValue,
        uint256 totalQScoreInPool,
        uint256 nextCosmicSurgeHour
    ) internal returns (uint256) {
        QuantumLotteryTypes.Draw storage draw = draws[hourId];
        draw.totalQScoreInPool = totalQScoreInPool;
        draw.randomValue = randomValue;
        draw.processingIndex = 0;
        draw.cumulativeScore = 0;
        draw.winnerPicked = false;
        draw.winnerIndex = type(uint256).max;
        draw.processingWrapped = false;
        // mark cosmic surge active for this draw if scheduled
        if (nextCosmicSurgeHour != type(uint256).max && hourId == nextCosmicSurgeHour) {
            draw.cosmicActive = true;
            nextCosmicSurgeHour = type(uint256).max;
        }
        // mark draw as RESOLVING
        draw.status = QuantumLotteryTypes.DrawStatus.RESOLVING;
        // (event emission handled by the caller)
        return nextCosmicSurgeHour;
    }
}
