// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryTypes} from "./QuantumLotteryTypes.sol";

library QuantumLotteryWithdraw {
    function computeWithdrawUnclaimed(
        mapping(uint256 => QuantumLotteryTypes.Draw) storage draws,
    uint256 hourId,
        uint256 currentBalance
    ) internal returns (uint256 toWithdraw) {
    QuantumLotteryTypes.Draw storage draw = draws[hourId];
        toWithdraw = draw.reservedRefunds;
    if (toWithdraw >= currentBalance) toWithdraw = currentBalance;
    require(toWithdraw != 0, "No funds to withdraw");
    // clear reserved refunds for this draw since we're sweeping funds (delete frees storage)
    delete draw.reservedRefunds;
        return toWithdraw;
    }
}
