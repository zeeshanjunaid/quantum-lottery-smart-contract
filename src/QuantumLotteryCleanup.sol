// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryCleanup {
    function cleanupDrawChunkStorage(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(uint256 => mapping(address => uint256)) storage participantIndexByHour,
        mapping(uint256 => mapping(address => bool)) storage refundClaimedByHour,
        uint256 hourId,
        uint256 iterations
    ) internal returns (bool done) {
        QuantumLotteryTypes.Draw storage draw = draws[hourId];

        uint256 pc = draw.participants.length;
        uint256 i = draw.cleanupIndex;
        uint256 end = i + iterations;
        if (end >= pc) end = pc;

        for (; i < end; ++i) {
            address paddr = draw.participants[i].playerAddress;
            if (paddr != address(0)) {
                delete participantIndexByHour[hourId][paddr];
                delete refundClaimedByHour[hourId][paddr];
            }
        }

        draw.cleanupIndex = i;
        if (draw.cleanupIndex >= pc) {
            // all cleaned; free participants array and clear flags
            delete draw.participants;
            draw.cleanupPending = false;
            draw.cleanupIndex = 0;
            return true;
        }
        return false;
    }
}
