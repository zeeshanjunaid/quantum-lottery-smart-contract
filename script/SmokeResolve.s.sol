// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

/// @notice Request a random winner for the previous hour
contract SmokeResolve is Script {
    function run() external returns (uint256 requestId) {
        address lottery = vm.envAddress("LOTTERY");
        uint256 hourId = block.timestamp / 3600;
        require(hourId > 0, "too early");

        uint256 targetHour = hourId - 1;
        console.log("Current hour:", hourId);
        console.log("Target hour to resolve:", targetHour);

        // Check draw status before attempting
        QuantumLotteryTypes.DrawStatus status = QuantumLottery(lottery).getDrawStatus(targetHour);
        console.log("Draw status:", uint8(status));
        console.log("0=OPEN, 1=CALCULATING_WINNER, 2=RESOLVING, 3=RESOLVED");

        if (status == QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER) {
            console.log("WARNING: Randomness already requested");
            return 0;
        }
        if (status == QuantumLotteryTypes.DrawStatus.RESOLVING) {
            console.log("WARNING: Draw is resolving");
            return 0;
        }
        if (status == QuantumLotteryTypes.DrawStatus.RESOLVED) {
            console.log("WARNING: Draw already resolved");
            return 0;
        }

        uint256 participants = QuantumLottery(lottery).getParticipantsCount(targetHour);
        console.log("Participants:", participants);

        if (participants == 0) {
            console.log("WARNING: No participants in this hour");
            return 0;
        }

        vm.startBroadcast();
        try QuantumLottery(lottery).requestRandomWinner(targetHour) returns (uint256 reqId) {
            requestId = reqId;
            console.log("SUCCESS: VRF request ID:", requestId);
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
            requestId = 0;
        }
        vm.stopBroadcast();
    }
}
