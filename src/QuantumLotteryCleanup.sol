// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryCleanup {
    function cleanupDrawChunkStorage(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        mapping(uint256 => mapping(address => uint256))
            storage s_participantIndexByHour,
        mapping(uint256 => mapping(address => bool))
            storage s_refundClaimedByHour,
        uint256 _hourId,
        uint256 _iterations
    ) internal returns (bool done) {
        QuantumLotteryTypes.Draw storage draw = draws[_hourId];

        uint256 pc = draw.participants.length;
        uint256 i = draw.cleanupIndex;
        uint256 end = i + _iterations;
        if (end > pc) end = pc;

        for (; i < end; i++) {
            address paddr = draw.participants[i].playerAddress;
            if (paddr != address(0)) {
                delete s_participantIndexByHour[_hourId][paddr];
                delete s_refundClaimedByHour[_hourId][paddr];
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
