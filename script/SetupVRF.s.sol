// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {VRFCoordinatorV2Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/// @notice Complete VRF setup: Create subscription, fund it, add consumer
contract SetupVRF is Script {
    function run() external returns (uint64 subId) {
        address link = vm.envAddress("LINK_TOKEN");
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        address lottery = vm.envAddress("LOTTERY");
        uint256 fundAmount = vm.envOr("LINK_AMOUNT", uint256(100000000000000000)); // 0.1 LINK default
        
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        uint256 balance = LinkTokenInterface(link).balanceOf(sender);
        
        console.log("=== VRF COMPLETE SETUP ===");
        console.log("LINK Token:", link);
        console.log("VRF Coordinator:", coordinator);
        console.log("Lottery Contract:", lottery);
        console.log("Sender:", sender);
        console.log("LINK Balance:", balance);
        console.log("Fund Amount:", fundAmount);
        
        if (balance < fundAmount) {
            console.log("ERROR: Insufficient LINK balance");
            console.log("Need at least:", fundAmount);
            return 0;
        }
        
        vm.startBroadcast();
        
        // Step 1: Create subscription
        console.log("Creating VRF subscription...");
        try VRFCoordinatorV2Interface(coordinator).createSubscription() returns (uint64 newSubId) {
            subId = newSubId;
            console.log("Subscription created:", subId);
        } catch Error(string memory reason) {
            console.log("Subscription creation failed:", reason);
            vm.stopBroadcast();
            return 0;
        }
        
        // Step 2: Fund subscription
        console.log("Funding subscription...");
        try LinkTokenInterface(link).transferAndCall(
            coordinator,
            fundAmount,
            abi.encode(subId)
        ) returns (bool ok) {
            if (ok) {
                console.log("Subscription funded with", fundAmount, "LINK");
            } else {
                console.log("Funding failed: transferAndCall returned false");
                vm.stopBroadcast();
                return subId;
            }
        } catch Error(string memory reason) {
            console.log("Funding failed:", reason);
            vm.stopBroadcast();
            return subId;
        }
        
        // Step 3: Add consumer
        console.log("Adding lottery as consumer...");
        try VRFCoordinatorV2Interface(coordinator).addConsumer(subId, lottery) {
            console.log("Consumer added successfully");
        } catch Error(string memory reason) {
            console.log("Add consumer failed:", reason);
            console.log("You may need to add manually");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== SETUP COMPLETE ===");
        console.log("Subscription ID:", subId);
        console.log("Update your .env file:");
        console.log("VRF_SUBSCRIPTION_ID=", subId);
        console.log("");
        console.log("VRF is ready for lottery draws!");
        
        return subId;
    }
}
