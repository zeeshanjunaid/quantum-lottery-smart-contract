// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";

/// @notice Process a resolved draw and cleanup in chunks
contract SmokeProcess is Script {
    function run() external returns (bool done) {
        address lottery = vm.envAddress("LOTTERY");
        uint256 hourId = vm.envUint("HOUR_ID");
        uint256 iterations = vm.envOr("ITER", uint256(50));
        vm.startBroadcast();
        done = QuantumLottery(lottery).processDrawChunk(hourId, iterations);
        if (done) {
            // Trigger storage cleanup in chunks as well
            while (!QuantumLottery(lottery).cleanupDrawChunk(hourId, iterations)) {
                // keep calling until true
            }
        }
        vm.stopBroadcast();
    }
}
