// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {QuantumLottery} from "../src/QuantumLottery.sol";
import {QuantumLotteryTypes} from "../src/QuantumLotteryTypes.sol";

/// @notice Complete lottery resolution: VRF request, wait, process, and show results
contract CompleteResolve is Script {
    function run() external {
        address lottery = vm.envAddress("LOTTERY");
        uint256 hourId = vm.envOr("HOUR_ID", uint256(0));

        if (hourId == 0) {
            // Default to previous hour
            hourId = block.timestamp / 3600 - 1;
        }

        console.log("=== COMPLETE LOTTERY RESOLUTION ===");
        console.log("Target hour:", hourId);
        console.log("Current timestamp:", block.timestamp);

        // Step 1: Check if we can resolve this hour
        QuantumLotteryTypes.DrawStatus status = QuantumLottery(lottery).getDrawStatus(hourId);
        console.log("Current status:", uint8(status));

        if (status == QuantumLotteryTypes.DrawStatus.RESOLVED) {
            console.log("Already resolved! Checking winner...");
            _showResults(lottery, hourId);
            return;
        }

        if (status == QuantumLotteryTypes.DrawStatus.OPEN) {
            uint256 participants = QuantumLottery(lottery).getParticipantsCount(hourId);
            console.log("Participants:", participants);

            if (participants == 0) {
                console.log("No participants - nothing to resolve");
                return;
            }

            console.log("Requesting VRF randomness...");
            vm.startBroadcast();
            try QuantumLottery(lottery).requestRandomWinner(hourId) returns (uint256 requestId) {
                console.log("VRF request successful, ID:", requestId);
                console.log("Status updated to CALCULATING_WINNER");
                console.log("Wait for VRF fulfillment, then run script again");
            } catch Error(string memory reason) {
                console.log("VRF request failed:", reason);
            }
            vm.stopBroadcast();
            return;
        }

        if (status == QuantumLotteryTypes.DrawStatus.CALCULATING_WINNER) {
            console.log("VRF requested, trying to process...");

            vm.startBroadcast();
            try QuantumLottery(lottery).processDrawChunk(hourId, 300) returns (bool done) {
                if (done) {
                    console.log("Draw processing complete!");
                    _showResults(lottery, hourId);
                } else {
                    console.log("Partial processing complete, run again for more");
                }
            } catch Error(string memory reason) {
                console.log("Processing failed:", reason);
                console.log("VRF might not be fulfilled yet");
            }
            vm.stopBroadcast();
            return;
        }

        console.log("Unexpected status, cannot proceed");
    }

    function _showResults(address lottery, uint256 hourId) internal view {
        console.log("");
        console.log("=== FINAL RESULTS ===");

        address winner = QuantumLottery(lottery).getWinner(hourId);
        uint256 pot = QuantumLottery(lottery).getPrizePot(hourId);
        uint256 payout = pot * 92 / 100;

        console.log("Winner:", winner);
        console.log("Total pot:", pot / 1000000, "USDC");
        console.log("Winner payout:", payout / 1000000, "USDC");
        console.log("");
        console.log("Use IdentifyWinner script to get winner name");
    }
}
