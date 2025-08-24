// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract RemoveVRFConsumerV2 is Script {
    function run() external {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint64 subId = uint64(vm.envUint("VRF_SUBSCRIPTION_ID"));
        address consumer = vm.envAddress("CONSUMER");

        vm.startBroadcast();
        VRFCoordinatorV2Interface(coordinator).removeConsumer(subId, consumer);
        vm.stopBroadcast();
    }
}
