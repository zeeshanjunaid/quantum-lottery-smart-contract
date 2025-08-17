// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryBase} from "./QuantumLotteryBase.sol";

contract QuantumLottery is QuantumLotteryBase {
    constructor(
        address _usdcAddress,
        address _treasuryAddress,
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _gasLane
    )
        QuantumLotteryBase(
            _usdcAddress,
            _treasuryAddress,
            _vrfCoordinator,
            _subscriptionId,
            _gasLane
        )
    {}
}
