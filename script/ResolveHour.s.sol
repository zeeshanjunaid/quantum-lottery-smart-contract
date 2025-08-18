// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";

/// @notice Request a random winner for a specific hour provided via env var HOUR_ID
contract ResolveHour is Script {
    function run() external returns (uint256 requestId) {
        address lottery = vm.envAddress("LOTTERY");
        uint256 hourId = vm.envUint("HOUR_ID");
        vm.startBroadcast();
        requestId = QuantumLottery(lottery).requestRandomWinner(hourId);
        vm.stopBroadcast();
    }
}
