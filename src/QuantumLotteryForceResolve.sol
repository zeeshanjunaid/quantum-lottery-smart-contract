// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryForceResolve {
    function forceResolveCore(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
        uint256 _hourId
    ) internal returns (uint256 participantCount) {
        QuantumLotteryTypes.Draw storage draw = draws[_hourId];
        draw.status = QuantumLotteryTypes.DrawStatus.RESOLVED;
        draw.forceResolved = true;
        draw.prizePot = 0;
        participantCount = draw.participants.length;
        return participantCount;
    }
}
