// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/// @notice Cancels a Chainlink VRF v2 (uint64) subscription and sends remaining LINK to WITHDRAW_TO.
/// Env vars required:
/// - VRF_COORDINATOR (address) — v2 coordinator address
/// - SUB_ID_TO_CANCEL_V2 (uint64) — subscription id to cancel
/// - WITHDRAW_TO (address) — recipient for refunded LINK
/// Broadcast with the subscription owner key.
contract CancelVRFSubV2 is Script {
    function run() external {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint64 subId = uint64(vm.envUint("SUB_ID_TO_CANCEL_V2"));
        address to = vm.envAddress("WITHDRAW_TO");

        vm.startBroadcast();
        VRFCoordinatorV2Interface(coordinator).cancelSubscription(subId, to);
        vm.stopBroadcast();
    }
}
