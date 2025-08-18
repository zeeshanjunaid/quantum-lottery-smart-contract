// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract CreateVRFSub is Script {
    function run() external returns (uint64 subId) {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        vm.startBroadcast();
        subId = VRFCoordinatorV2Interface(coordinator).createSubscription();
        vm.stopBroadcast();
        return subId;
    }
}
