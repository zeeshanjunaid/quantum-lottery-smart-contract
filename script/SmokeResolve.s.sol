// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";

/// @notice Request a random winner for the previous hour
contract SmokeResolve is Script {
    function run() external returns (uint256 requestId) {
        address lottery = vm.envAddress("LOTTERY");
        vm.startBroadcast();
        // Compute previous hour id. This tx must be sent after the hour rolls over.
        uint256 hourId = block.timestamp / 3600;
        require(hourId > 0, "too early");
        requestId = QuantumLottery(lottery).requestRandomWinner(hourId - 1);
        vm.stopBroadcast();
    }
}
