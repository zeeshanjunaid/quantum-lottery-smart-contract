// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LinkTokenInterface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

/// @notice Fund a Chainlink VRF v2 Subscription using LINK transferAndCall
contract FundVRFSub is Script {
    function run() external {
        address link = vm.envAddress("LINK_TOKEN");
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint64 subId = uint64(vm.envUint("VRF_SUBSCRIPTION_ID"));
        uint256 amount = vm.envOr("LINK_AMOUNT", uint256(100000000000000000)); // default 0.1 LINK
        
        // Check sender balance first
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        uint256 balance = LinkTokenInterface(link).balanceOf(sender);
        
        console.log("=== VRF SUBSCRIPTION FUNDING ===");
        console.log("LINK Token:", link);
        console.log("VRF Coordinator:", coordinator);
        console.log("Subscription ID:", subId);
        console.log("Sender:", sender);
        console.log("Current LINK balance:", balance);
        console.log("Requested amount:", amount);
        
        if (balance < amount) {
            console.log("ERROR: Insufficient LINK balance");
            console.log("Required:", amount);
            console.log("Available:", balance);
            console.log("Need:", amount - balance, "more LINK");
            return;
        }

        vm.startBroadcast();
        try LinkTokenInterface(link).transferAndCall(
            coordinator,
            amount,
            abi.encode(subId)
        ) returns (bool ok) {
            if (ok) {
                console.log("SUCCESS: Funded subscription with", amount, "LINK");
            } else {
                console.log("FAILED: transferAndCall returned false");
            }
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        }
        vm.stopBroadcast();
    }
}
