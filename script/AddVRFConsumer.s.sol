// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IVRFSubscriptionV2Plus} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

contract AddVRFConsumer is Script {
    function run() external {
    address coordinator = vm.envAddress("VRF_COORDINATOR");
    uint256 subId = vm.envUint("VRF_SUBSCRIPTION_ID");
        address consumer = vm.envAddress("CONSUMER");

        vm.startBroadcast();
    IVRFSubscriptionV2Plus(coordinator).addConsumer(subId, consumer);
        vm.stopBroadcast();
    }
}
