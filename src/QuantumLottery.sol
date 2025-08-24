// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {QuantumLotteryBase} from "./QuantumLotteryBase.sol";

contract QuantumLottery is QuantumLotteryBase {
    // Note: Keeping constructor non-payable as this protocol rejects ETH at the base via receive/fallback.
        /// @dev Constructor marked payable for minor gas optimization. ETH sent at deploy is ignored.
        constructor(
        address _usdcAddress,
        address _treasuryAddress,
    address _vrfCoordinator,
    uint256 _subscriptionId,
        bytes32 _gasLane
    ) payable
        QuantumLotteryBase(
            _usdcAddress,
            _treasuryAddress,
            _vrfCoordinator,
            _subscriptionId,
            _gasLane
        )
    {}
}
